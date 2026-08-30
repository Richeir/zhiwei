import Foundation
import os
import UIKit
import WebKit

// MARK: - 离屏 WKWebView 宿主（PLAN D9 车道① 的物理载体 / R7 判据①）
//
// R7 判据①：「常驻离屏/隐藏的 WKWebView 是否被系统挂起」。原生已知解法两条：
//   A. 入屏 1×1 子视图（挂到 keyWindow，视觉上几乎不可见，但拿到了"在屏"资格）
//   B. 独立 UIWindow（自建低层级窗口承载，不依赖别人的视图树）
// 本类把两条都实现成可切换策略，**spike 期实测哪条在 iOS 26 上真能常驻**；
// 两条都失败时按 R7 预案降级为"常驻可见小窗"（M1 定案）。
//
// 这是 M0 的 spike 级实现（可抛弃），生产化在 M1：补前后台/锁屏恢复、导航失败重试、
// 页面崩溃（`webViewWebContentProcessDidTerminate`）后的重建与会话回灌。

/// 通道页注入脚本：定义 `__zw` 命名空间，负责同源 fetch + 分片回传。
enum ChannelScript {
    /// 消息通道名（JS 侧 `webkit.messageHandlers.zhiwei`）
    static let messageName = "zhiwei"

    /// 分片大小（字符）。WebKit 消息体有大小限制，大回包必须切片——这也是
    /// "为什么需要 `WKScriptMessageHandlerWithReply` 而不是只看 evaluateJavaScript 返回值"的理由。
    static let chunkChars = 40000

    static let bootstrap: String = """
    (() => {
      if (window.__zw && window.__zw.version === 1) { return; }
      const CHUNK = \(chunkChars);
      const ship = async (meta, text) => {
        const total = Math.max(1, Math.ceil(text.length / CHUNK));
        for (let i = 0; i < total; i++) {
          const payload = Object.assign({}, meta, {
            chunk: i, total: total, data: text.slice(i * CHUNK, (i + 1) * CHUNK)
          });
          // 有回复通道时 postMessage 返回 Promise：拿到 ack 再发下一片（背压）
          await webkit.messageHandlers.\(messageName).postMessage(payload);
        }
      };
      window.__zw = {
        version: 1,
        ping() {
          return { href: location.href, ready: document.readyState, title: document.title };
        },
        async request(req) {
          try {
            const init = { method: req.method || 'GET', credentials: 'include', headers: req.headers || {} };
            if (req.body) { init.body = req.body; }
            const resp = await fetch(req.url, init);
            const text = await resp.text();
            await ship({
              id: req.id, status: resp.status, redirected: resp.redirected,
              finalUrl: resp.url, contentType: (resp.headers.get('content-type') || ''), error: null
            }, text);
            return { id: req.id, status: resp.status, ok: true };
          } catch (e) {
            await ship({ id: req.id, status: -1, contentType: '', finalUrl: '', error: String(e) }, '');
            return { id: req.id, status: -1, ok: false, error: String(e) };
          }
        }
      };
    })();
    """
}

/// 回传的单个分片（结构化协议：请求 ID ↔ 分片序号 ↔ 总片数）
struct ChannelChunk: Sendable {
    var id: UUID
    var status: Int
    var contentType: String
    var finalURL: String?
    var errorMessage: String?
    var index: Int
    var total: Int
    var text: String
}

/// 消息中继：把 WebKit 的回调转交给通道所有者。
///
/// 为什么单独一个类：`WKUserContentController` 会**强引用**它的 handler。
/// 若让宿主自己当 handler，就形成 宿主 → webView → config → controller → 宿主 的循环引用。
/// 中继只持 weak owner，环就断了。
/// 分片接收方（用协议而非闭包：`weak` 不能修饰闭包属性）
@MainActor
protocol ChannelChunkSink: AnyObject {
    func receive(_ chunk: ChannelChunk)
}

@MainActor
final class ChannelMessageRelay: NSObject, WKScriptMessageHandlerWithReply {
    weak var sink: (any ChannelChunkSink)?

    /// Swift 6 语言模式下 WebKit 把本协议只导入成 async 形态：
    /// 返回 `(reply, errorMessage)` 即等价于旧 `replyHandler(reply, errorMessage)`，
    /// JS 侧 `postMessage(...)` 的 Promise 据此 resolve / reject，分片 ack 节奏不变。
    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard message.name == ChannelScript.messageName,
              let body = message.body as? [String: Any],
              let id = UUID(uuidString: body["id"] as? String ?? ""),
              let index = body["chunk"] as? Int,
              let total = body["total"] as? Int else {
            return (nil, "malformed zhiwei message")
        }
        let chunk = ChannelChunk(
            id: id,
            status: (body["status"] as? Int) ?? -1,
            contentType: (body["contentType"] as? String) ?? "",
            finalURL: body["finalUrl"] as? String,
            errorMessage: body["error"] as? String,
            index: index,
            total: total,
            text: (body["data"] as? String) ?? "")
        sink?.receive(chunk)
        // ack：让页面继续发下一片
        return (["ack": true, "chunk": index], nil)
    }
}

/// 离屏 WebView 宿主。
@MainActor
final class ChannelWebViewHost: NSObject, WKNavigationDelegate {
    enum SurvivalStrategy: String, CaseIterable, Sendable {
        /// A：塞进 keyWindow 的 1×1 子视图
        case hiddenSubview
        /// B：独立 UIWindow 承载
        case floatingWindow
        /// 纯离屏（不放进任何窗口层级）——对照组，用来确认"隐藏是否等于挂起"
        case detached
    }

    private(set) var webView: WKWebView
    let relay = ChannelMessageRelay()

    private var strategy: SurvivalStrategy
    private var floatingWindow: UIWindow?
    private var readyContinuations: [CheckedContinuation<Void, any Error>] = []
    private(set) var isPageReady = false

    /// WebContent 进程被终止的回调（R7 判据① 的观测点）
    var onProcessTerminate: (() -> Void)?

    init(strategy: SurvivalStrategy = .hiddenSubview, dataStore: WKWebsiteDataStore = .default()) {
        self.strategy = strategy

        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.addUserScript(
            WKUserScript(
                source: ChannelScript.bootstrap,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page))

        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.alpha = 0.01
        web.isHidden = false
        web.scrollView.isScrollEnabled = false

        self.webView = web
        super.init()

        config.userContentController.addScriptMessageHandler(relay, contentWorld: .page, name: ChannelScript.messageName)
        web.navigationDelegate = self
        installIntoViewHierarchy()
    }

    /// 切换保活策略（R7 判据① 的 spike 开关）
    func setStrategy(_ next: SurvivalStrategy) {
        guard next != strategy else { return }
        strategy = next
        detachFromViewHierarchy()
        installIntoViewHierarchy()
    }

    var currentStrategy: SurvivalStrategy {
        strategy
    }

    /// 通道页：移动 UA 下 weibo.com 会 302 跳到 m 站，故直接以 m 站为同源入口，
    /// 保证车道① 页面内 fetch 与 m 站接口同源（不触发 CORS preflight）。
    static let channelURL = URL(string: "https://m.weibo.cn/")!

    /// 加载通道页并等 document 就绪（超时即视为判据① 失败的前兆之一）
    func loadChannelPage(timeout: Duration = .seconds(20)) async throws {
        isPageReady = false
        _ = webView.load(URLRequest(url: Self.channelURL, cachePolicy: .reloadRevalidatingCacheData))
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.waitForReady() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ChannelHostError.timeout
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func waitForReady() async throws {
        if isPageReady {
            return
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            readyContinuations.append(cont)
        }
    }

    /// 在页面上下文里执行 JS（车道① 的注入点）
    func evaluate(_ source: String) async throws -> Any? {
        try await webView.evaluateJavaScript(source, in: nil, contentWorld: .page)
    }

    /// 探测页面侧 JS 是否存活（R7 判据② 的基本动作）
    func ping() async throws -> [String: Any] {
        let raw = try await evaluate("window.__zw ? JSON.stringify(window.__zw.ping()) : '{\"missing\":true}'")
        guard let text = raw as? String, let data = text.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["missing": true]
        }
        return dict
    }

    /// 注入 JS 字面量安全转义（把请求对象塞进 `__zw.request(...)` 前必须过这里）
    static func jsLiteral(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 保活：两条策略都实现

    private func installIntoViewHierarchy() {
        switch strategy {
        case .detached:
            return
        case .hiddenSubview:
            guard let window = Self.keyWindow() else { return }
            webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            webView.autoresizingMask = []
            webView.isUserInteractionEnabled = false
            window.addSubview(webView)
        case .floatingWindow:
            let window: UIWindow = if let scene = Self.activeWindowScene() {
                UIWindow(windowScene: scene)
            } else {
                UIWindow(frame: UIScreen.main.bounds)
            }
            window.windowLevel = UIWindow.Level.normal - 10
            window.isUserInteractionEnabled = false
            window.backgroundColor = .clear
            webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            window.rootViewController = UIViewController()
            window.rootViewController?.view.addSubview(webView)
            window.isHidden = false
            floatingWindow = window
        }
    }

    private func detachFromViewHierarchy() {
        webView.removeFromSuperview()
        floatingWindow?.isHidden = true
        floatingWindow?.rootViewController = nil
        floatingWindow = nil
    }

    /// 唤起可见形态（R1 缓解措施③：把离屏宿主临时变成人机验证界面）
    func makeVisible(_ url: URL) {
        if webView.superview == nil {
            installIntoViewHierarchy()
        }
        webView.isHidden = false
        webView.alpha = 1
        webView.isUserInteractionEnabled = true
        if let container = webView.superview {
            let bounds = container.bounds
            let side = CGSize(width: min(420, bounds.width - 32), height: min(560, max(320, bounds.height - 80)))
            webView.frame = CGRect(
                x: (bounds.width - side.width) / 2,
                y: (bounds.height - side.height) / 2,
                width: side.width, height: side.height)
        }
        webView.load(URLRequest(url: url))
    }

    /// 回到离屏保活形态
    func makeHidden() {
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    private static func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private static func keyWindow() -> UIWindow? {
        activeWindowScene()?
            .windows
            .first { $0.isKeyWindow } ?? activeWindowScene()?.windows.first
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_: WKWebView, didFinish _: WKNavigation!) {
        Task { @MainActor in self.markReady() }
    }

    nonisolated func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        Task { @MainActor in self.markFailed(error) }
    }

    /// WebContent 进程被杀/挂起（R7 判据① 的失败信号，spike 里作为观测点）
    nonisolated func webViewWebContentProcessDidTerminate(_: WKWebView) {
        Task { @MainActor in
            self.isPageReady = false
            Logger.log(domain: .channel).error("web content process terminated (R7 判据①信号)")
            self.markFailed(ChannelHostError.processTerminated)
            self.onProcessTerminate?()
        }
    }

    private func markReady() {
        isPageReady = true
        let pending = readyContinuations
        readyContinuations.removeAll()
        for cont in pending {
            cont.resume()
        }
    }

    private func markFailed(_ error: any Error) {
        let pending = readyContinuations
        readyContinuations.removeAll()
        for cont in pending {
            cont.resume(throwing: error)
        }
    }

    enum ChannelHostError: Error, Sendable {
        case processTerminated
        case timeout
    }
}
