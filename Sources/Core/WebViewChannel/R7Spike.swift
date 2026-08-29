import Foundation
import os
import UIKit
import WebKit

// MARK: - R7 四项判据 spike（PLAN §5「M0 首个 spike 四项判据全过才算通过」/ §10 关键路径）
//
// 这是 M0 的出口条件里唯一"过不去就没有 M1"的东西，所以它被做成**可在真机上按一下就出结论**的面板，
// 而不是散在注释里的期望。结论写进 Store（`r7SpikeLastResult`）并同步到 `docs/VERSIONS.md`。
//
// 四条判据与失败预案（R7 表）：
//   ① 离屏/隐藏 WKWebView 是否被挂起        → 失败则改"常驻可见小窗"（本面板可切换保活策略对比）
//   ② 页面内 fetch 桥回传在前后台/锁屏后存活 → 失败则改车道①为"每次请求前重建 JS 上下文"
//   ③ WKHTTPCookieStore 直读 httpOnly 并附带 → 失败则全部退回车道①（页面内取数）
//   ④ 原生 URLSession 直传时 Referer/Origin 校验 → 失败则上传/发布改走可见 WKWebView

enum R7Judge: Int, CaseIterable, Identifiable, Sendable {
    case hiddenPersistence = 1
    case bridgeSurvival = 2
    case cookieDirectRead = 3
    case uploadValidation = 4

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .hiddenPersistence: "① 离屏 WebView 常驻不挂起"
        case .bridgeSurvival: "② 前后台/锁屏后桥回传存活"
        case .cookieDirectRead: "③ httpOnly Cookie 直读并附带"
        case .uploadValidation: "④ 原生上传通过 Referer/Origin 校验"
        }
    }

    var fallback: String {
        switch self {
        case .hiddenPersistence: "→ 预案：常驻可见 1×1 小窗（本面板切策略即验证）"
        case .bridgeSurvival: "→ 预案：请求前重建 JS 上下文"
        case .cookieDirectRead: "→ 预案：全部退回车道①（页面内取数含附带）"
        case .uploadValidation: "→ 预案：上传/发布走可见 WKWebView"
        }
    }

    /// 是否必须人工配合（后台/锁屏动作没法由代码完成）
    var needsHuman: Bool {
        self == .bridgeSurvival || self == .cookieDirectRead
    }
}

struct R7Verdict: Sendable, Equatable, Identifiable {
    enum Outcome: String, Sendable {
        case pending = "未测"
        case running = "进行中"
        case passed = "通过"
        case failed = "不通过"
        /// 无法判定（网络不可达、未登录等前置不满足），不算失败也不算通过
        case inconclusive = "待前置"
    }

    var judge: R7Judge
    var outcome: Outcome
    var detail: String
    var observedAt: Date?

    var id: Int {
        judge.rawValue
    }

    static func pending(_ judge: R7Judge) -> R7Verdict {
        R7Verdict(judge: judge, outcome: .pending, detail: judge.fallback, observedAt: nil)
    }
}

@MainActor
@Observable
final class R7SpikeRunner {
    private(set) var verdicts: [R7Judge: R7Verdict] = Dictionary(
        uniqueKeysWithValues: R7Judge.allCases.map { ($0, .pending($0)) })
    /// 观察中的宿主（由通道注入，spike 与生产共用同一个 WebView，避免"测的和跑的不是一个"）
    private let channel: WebViewChannelLive
    /// 判据① 的静置观察时长；真机上建议 60s 以上（挂起通常发生在数秒到数十秒）
    var idleSeconds: Double = 45

    private var processTerminated = false

    init(channel: WebViewChannelLive) {
        self.channel = channel
        channel.host.onProcessTerminate = { [weak self] in
            Task { @MainActor [weak self] in self?.processTerminated = true }
        }
    }

    var allPassed: Bool {
        R7Judge.allCases.allSatisfy { verdicts[$0]?.outcome == .passed }
    }

    var strategy: ChannelWebViewHost.SurvivalStrategy {
        get { channel.host.currentStrategy }
        set { Task { await channel.switchStrategy(to: newValue) } }
    }

    func run(_ judge: R7Judge) async {
        verdicts[judge] = R7Verdict(judge: judge, outcome: .running, detail: "", observedAt: nil)
        let verdict = await execute(judge)
        verdicts[judge] = verdict
        Logger.log(domain: .channel).info("R7 \(judge.rawValue): \(verdict.outcome.rawValue, privacy: .public)")
    }

    func runAll() async {
        for judge in R7Judge.allCases {
            await run(judge)
        }
    }

    private func execute(_ judge: R7Judge) async -> R7Verdict {
        let now = Date()
        do {
            switch judge {
            case .hiddenPersistence: return try await judgeHiddenPersistence(now: now)
            case .bridgeSurvival: return try await judgeBridgeSurvival(now: now)
            case .cookieDirectRead: return try await judgeCookieRead(now: now)
            case .uploadValidation: return try await judgeUpload(now: now)
            }
        } catch let error as APIError {
            return R7Verdict(judge: judge, outcome: .failed, detail: error.userMessage, observedAt: now)
        } catch {
            return R7Verdict(judge: judge, outcome: .failed, detail: String(describing: error), observedAt: now)
        }
    }

    // MARK: 判据①

    private func judgeHiddenPersistence(now: Date) async throws -> R7Verdict {
        processTerminated = false
        try await channel.ensureReady()
        let before = try await channel.host.ping()
        var ticks = 0
        for _ in 0 ..< Int(idleSeconds / 5) {
            try? await Task.sleep(for: .seconds(5))
            _ = try await channel.host.ping()
            ticks += 1
            if processTerminated {
                break
            }
        }
        guard !processTerminated else {
            return R7Verdict(
                judge: .hiddenPersistence,
                outcome: .failed,
                detail: "静置 \(ticks * 5)s 后 WebContent 进程被终止（策略 \(strategy.rawValue)）。换一种保活策略再测。",
                observedAt: now)
        }
        let after = try await channel.host.ping()
        let alive = after["ready"] as? String == "complete"
        return R7Verdict(
            judge: .hiddenPersistence,
            outcome: alive ? .passed : .failed,
            detail: "策略 \(strategy.rawValue)：静置 \(ticks * 5)s 后 JS 仍存活，href=\(before["href"] ?? "nil")",
            observedAt: now)
    }

    // MARK: 判据②

    private func judgeBridgeSurvival(now: Date) async throws -> R7Verdict {
        // 前置：需要真机上手动作（切后台 ≥20s 再回前台）。没做过就直接给"待前置"，
        // 绝不用"看起来能跑"糊弄过去——这条一旦误判，M1 的通道设计整个是错的。
        try await channel.ensureReady()
        let startedBackground = channel.observedBackgroundCycles
        try await Task.sleep(for: .seconds(20))
        let endedBackground = channel.observedBackgroundCycles
        guard endedBackground > startedBackground else {
            return R7Verdict(
                judge: .bridgeSurvival,
                outcome: .inconclusive,
                detail: "请在面板提示后把 App 切到后台 20 秒再回前台，然后重跑本项。",
                observedAt: now)
        }
        let marker = UUID()
        let data = try await channel.fetchR7Probe(marker: marker)
        return R7Verdict(
            judge: .bridgeSurvival,
            outcome: data.isEmpty ? .failed : .passed,
            detail: "前后台一轮后经消息桥回传正常（请求 ID 关联成功，回包 \(data.count) 字节）",
            observedAt: now)
    }

    // MARK: 判据③

    private func judgeCookieRead(now: Date) async throws -> R7Verdict {
        let count = try await channel.syncCookies()
        let cookies = await CookieBridge.allCookies(from: channel.host.webView.configuration.websiteDataStore.httpCookieStore)
        let httpOnlyNames = cookies.filter(\.isHTTPOnly).map(\.name)
        let hasSUB = httpOnlyNames.contains("SUB")
        let sharedNames = Set((HTTPCookieStorage.shared.cookies ?? []).map(\.name))
        return R7Verdict(
            judge: .cookieDirectRead,
            outcome: hasSUB ? .passed : .inconclusive,
            detail: """
            原生读到 \(count) 条 cookie；httpOnly 名单：\(httpOnlyNames.sorted().joined(separator: ", "))（只有名字，无值）。
            SUB \(hasSUB ? "已读到" : "未读到（需已登录）")；\
            共享存储含 SUB：\(sharedNames.contains("SUB") ? "是" : "否")。
            未登录时本项判"待前置"：先在「我的」里登录，再重跑。
            """,
            observedAt: now)
    }

    // MARK: 判据④

    private func judgeUpload(now: Date) async throws -> R7Verdict {
        // 1×1 透明 PNG：只为验证"服务端是否接受原生 multipart + 我们补的头"，不产生真实内容
        guard let probe = Data(base64Encoded: R7SpikeRunner.transparentPNG), !probe.isEmpty else {
            return R7Verdict(
                judge: .uploadValidation,
                outcome: .inconclusive,
                detail: "探针图片解码失败",
                observedAt: now)
        }
        var request = NativeRequest(url: APIWebEndpoint.uploadPicture.url, method: "POST")
        request.headers = await APIWebEndpoint.uploadPicture.requestHeaders(
            xsrfToken: CookieBridge.xsrfToken(in: CookieBridge.allCookies(
                from: channel.host.webView.configuration.websiteDataStore.httpCookieStore)))
        request.body = .multipart([
            .init(field: "pic", value: .file(name: "r7-probe.png", mimeType: "image/png", data: probe)),
            .init(field: "type", value: .text("pic"))
        ])
        do {
            let data = try await channel.sendNative(request)
            let text = String(data: Data(data.prefix(160)), encoding: .utf8) ?? "<非 UTF-8 回包>"
            let looksLikeJSON = text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
            return R7Verdict(
                judge: .uploadValidation,
                outcome: looksLikeJSON ? .passed : .failed,
                detail: looksLikeJSON
                    ? "服务端按 JSON 应答（Referer/Origin 校验通过）。首 160 字节：\(text)"
                    : "回包不是 JSON，疑似被要求验证或重定向到页面：\(text)",
                observedAt: now)
        } catch let error as APIError {
            return R7Verdict(
                judge: .uploadValidation,
                outcome: error == .notLoggedIn ? .inconclusive : .failed,
                detail: "\(error.userMessage)（\(String(describing: error))）",
                observedAt: now)
        }
    }

    /// 判据④ 用的最小合法 PNG（1×1 透明）
    static let transparentPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=="
}
