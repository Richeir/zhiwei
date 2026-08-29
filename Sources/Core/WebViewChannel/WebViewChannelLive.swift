import Foundation
import os
import UIKit
import WebKit

// MARK: - 双车道通道（PLAN D9 路线 B / §5 定样 / M1 生产化的起点）
//
/// 注意：本类是 **M0 spike 级实现**——四项判据能跑、能观测、能得出定案结论即可；
/// 页面重建、会话回灌、跨前后台的存活细节归 M1（PLAN §5 边界说明）。
@MainActor
final class WebViewChannelLive: WebViewChannel, ChannelChunkSink {
    enum Signal {
        /// 风控挑战出现（Auth 域监听，唤起可见验证界面）
        static let punishChallenge = Notification.Name("dev.zhiwei.channel.punishChallenge")
        /// 人工验证完成（UI 调用 `resumeAfterVerification()` 时发）
        static let verificationFinished = Notification.Name("dev.zhiwei.channel.verificationFinished")
    }

    /// 挂起中的请求：分片按序号归位，齐了才拼回完整回包
    private struct Pending {
        var meta: ChannelChunk?
        var parts: [Int: String] = [:]
        var expectedTotal: Int = 0
        var cont: CheckedContinuation<Data, any Error>
    }

    private(set) var state: ChannelState = .idle

    let host: ChannelWebViewHost
    private let limiter: RateLimiter
    private let deduper = InFlightDeduper()
    private let policy: RateLimitPolicy
    private let clock: any MonotonicClock
    private let nativeSession: URLSession

    private var pending: [UUID: Pending] = [:]
    /// 观测计数（R7 spike 面板用）
    private(set) var pageFetchCount = 0
    private(set) var nativeSendCount = 0
    /// 进入后台的轮次（R7 判据② 需要"真的经历过一次前后台"，不能靠模拟）
    private(set) var observedBackgroundCycles = 0

    init(
        policy: RateLimitPolicy = .standard,
        clock: any MonotonicClock = SystemMonotonicClock(),
        strategy: ChannelWebViewHost.SurvivalStrategy = .hiddenSubview) {
        self.policy = policy
        self.clock = clock
        self.limiter = RateLimiter(policy: policy, clock: clock)
        self.host = ChannelWebViewHost(strategy: strategy)

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared // Cookie 由 `syncCookies()` 从 WebKit 搬来
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = TimeInterval(policy.timeoutNanos / 1_000_000_000)
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        self.nativeSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)

        host.relay.sink = self

        // 自己订阅生命周期：判据② 要的是"系统真实挂起过我们"，所以计数必须来自真通知
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.observedBackgroundCycles += 1 }
            }
    }

    /// R7 判据② 专用：走车道①做一次同源探测请求，验证"请求 ID ↔ 分片回包"的关联在前后台之后仍然成立。
    /// 只取回包字节数，不解析内容（内容正确性由判据③④与 M2 契约快照负责）。
    func fetchR7Probe(marker: UUID) async throws -> Data {
        let request = WebChannelRequest(
            url: APIWebEndpoint.sessionProbe.url,
            method: .get,
            query: ["_probe": marker.uuidString],
            headers: APIWebEndpoint.sessionProbe.requestHeaders(),
            id: marker)
        return try await fetch(request)
    }

    /// 真机 UA：风控对 UA 敏感（R1），保持与 Mobile Safari 一致，不自造标识
    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_5 like Mac OS X) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1"

    // MARK: - 生命周期

    /// 确保离屏 WebView 已加载通道页（车道① 的前置）
    func ensureReady() async throws {
        switch state {
        case .ready where host.isPageReady: return
        case .punished: try await waitUntilReady()
        default: break
        }
        do {
            try await host.loadChannelPage()
            state = .ready
        } catch {
            state = .suspended
            throw APIError.channelUnavailable(reason: String(describing: error))
        }
    }

    /// 切换保活策略（R7 判据① spike 开关）
    func switchStrategy(to next: ChannelWebViewHost.SurvivalStrategy) async {
        host.setStrategy(next)
        state = .idle
        Logger.log(domain: .channel).info("survival strategy → \(next.rawValue, privacy: .public)")
    }

    // MARK: - 车道①：页面内 fetch + 分片回传

    func fetch(_ request: WebChannelRequest) async throws -> Data {
        guard request.isAllowedHost else { throw APIError.forbiddenTarget(request.url) }
        let key = Self.signature(of: request)

        // 1. 在途合并：同样的请求只发一次
        if let shared = try await deduper.join(key) {
            Logger.log(domain: .channel).debug("dedup hit: \(key.prefix(60), privacy: .public)")
            return shared
        }

        do {
            let data = try await gated { [self] in
                try await pageFetch(request)
            }
            await deduper.publish(key, with: .success(data))
            return data
        } catch {
            await deduper.publish(key, with: .failure(error))
            throw error
        }
    }

    private func pageFetch(_ request: WebChannelRequest) async throws -> Data {
        try await ensureReady()
        guard host.isPageReady else { throw APIError.channelUnavailable(reason: "page not ready") }

        let payload = PageFetchRequest(
            id: request.id.uuidString,
            url: Self.absolute(request.url, query: request.query).absoluteString,
            method: request.method.rawValue,
            headers: Self.headers(for: request),
            body: request.form.isEmpty ? nil : Self.formEncoded(request.form))
        guard let literal = ChannelWebViewHost.jsLiteral(payload) else {
            throw APIError.transport(reason: "request literal encode failed")
        }

        pageFetchCount += 1
        Logger.log(domain: .channel).debug("lane① \(payload.method, privacy: .public) fetch")

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, any Error>) in
            pending[request.id] = Pending(cont: cont)
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    // JS 侧把数据经消息桥分片回传；这里的返回值只是"发完了"的摘要
                    _ = try await self.host.evaluate("__zw.request(\(literal));")
                } catch {
                    self.fail(request.id, with: error)
                }
            }
            // 超时保护：JS 侧不回包（页面被挂起、进程被杀）时不能把调用方永久吊住
            Task { @MainActor [weak self] in
                try? await self?.clock.sleep(nanos: self?.policy.timeoutNanos ?? 12_000_000_000)
                self?.fail(request.id, with: APIError.timeout, onlyIfPending: true)
            }
        }
    }

    /// `ChannelChunkSink`：分片归位，齐包后续航
    func receive(_ chunk: ChannelChunk) {
        guard var entry = pending[chunk.id] else { return }
        entry.meta = chunk
        entry.expectedTotal = chunk.total
        entry.parts[chunk.index] = chunk.text
        if entry.parts.count >= chunk.total {
            pending[chunk.id] = nil
            let assembled = (0 ..< chunk.total).compactMap { entry.parts[$0] }.joined()
            let data = Data(assembled.utf8)

            if let error = Self.error(for: chunk, body: data) {
                entry.cont.resume(throwing: error)
                return
            }
            entry.cont.resume(returning: data)
        } else {
            pending[chunk.id] = entry
        }
    }

    private func fail(_ id: UUID, with error: any Error, onlyIfPending: Bool = false) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        if onlyIfPending {
            entry.cont.resume(throwing: APIError.timeout)
            return
        }
        entry.cont.resume(throwing: (error as? APIError) ?? .transport(reason: String(describing: error)))
    }

    /// 状态码/内容 → 错误（命中风控就把状态机推到 `.punished`）
    private static func error(for chunk: ChannelChunk, body: Data) -> APIError? {
        if let message = chunk.errorMessage, !message.isEmpty {
            return .transport(reason: message)
        }
        let classified = APIError.classify(statusCode: chunk.status, body: body, contentType: chunk.contentType)
        if case .some(.punished) = classified {
            return classified
        }
        if case .some(.notLoggedIn) = classified {
            return classified
        }
        return classified
    }

    // MARK: - 车道②：原生 URLSession（上传/发布主用）

    func sendNative(_ request: NativeRequest) async throws -> Data {
        guard WebChannelRequest.allowedHosts.contains(where: { request.url.host?.hasSuffix($0) == true }) else {
            throw APIError.forbiddenTarget(request.url)
        }
        return try await gated { [self] in
            try await nativeSend(request)
        }
    }

    private func nativeSend(_ request: NativeRequest) async throws -> Data {
        // 每次原生请求前重新同步 cookie：WebKit 侧过期/被踢时能第一时间反映（R2）
        _ = try await syncCookies()

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in Self.nativeDefaults(adding: request.headers) {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        switch request.body {
        case .none:
            break
        case .form(let fields):
            urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = Data(Self.formEncoded(fields).utf8)
        case .multipart(let parts):
            let boundary = "----ZhiWei\(UUID().uuidString)"
            urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = Data(Self.multipartBody(parts, boundary: boundary))
        }

        nativeSendCount += 1
        Logger.log(domain: .channel).debug("lane② \(request.method, privacy: .public) native")

        let (data, response) = try await nativeSession.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(reason: "non-http response")
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        if let error = APIError.classify(statusCode: http.statusCode, body: data, contentType: contentType) {
            handlePunishedIfNeeded(error)
            throw error
        }
        return data
    }

    // MARK: - 会话探测（R7 判据③ 的落地入口）

    func probeSession() async throws -> SessionProbe {
        let started = Date()
        let cookieCount = try await syncCookies()
        let cookies = await CookieBridge.allCookies(
            from: host.webView.configuration.websiteDataStore.httpCookieStore)
        let hasLogin = CookieBridge.hasLoginCookies(cookies)

        // 轻量探测端点：不依赖页面上下文，纯原生直发（端点以实测为准，收敛在 APIWeb）
        var request = NativeRequest(url: APIWebEndpoint.sessionProbe.url, method: "GET")
        request.headers = ["Referer": APIWebEndpoint.sessionProbe.referer?.absoluteString ?? "",
                           "Accept": "application/json"]
        let data = try await sendNative(request)
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)

        let uid = (try? JSONDecoder().decode(SessionProbeDTO.self, from: data))?.uid
        let probe = SessionProbe(
            isLoggedIn: uid != nil && hasLogin,
            uid: uid,
            sawLoginCookies: hasLogin,
            elapsedMilliseconds: elapsed)
        state = probe.isLoggedIn ? .ready : .signedOut
        Logger.log(domain: .auth).info("probe: logged=\(probe.isLoggedIn, privacy: .public) cookies=\(cookieCount, privacy: .public)")
        return probe
    }

    /// 兼容两种探测端点口径：`{"login":true}` 与 `{"data":{"uid":"..."}}`
    private struct SessionProbeDTO: Decodable {
        var uid: String?
        init(from decoder: any Decoder) throws {
            let top = try decoder.container(keyedBy: DynamicKey.self)
            if let login = try? top.decode(Bool.self, forKey: DynamicKey("login")), login {
                uid = "probe:login"
                return
            }
            if let nested = try? top.decode([String: String].self, forKey: DynamicKey("data")) {
                uid = nested["uid"]
            }
        }
    }

    // MARK: - Cookie 同步

    /// WebKit → `HTTPCookieStorage.shared`。返回同步条数（永不返回内容）。
    @discardableResult
    func syncCookies() async throws -> Int {
        let cookies = await CookieBridge.allCookies(
            from: host.webView.configuration.websiteDataStore.httpCookieStore)
        let count = CookieBridge.syncToSharedStorage(cookies)
        if !CookieBridge.hasLoginCookies(cookies), state == .ready {
            state = .signedOut // R2：会话掉线要有明确状态，而不是等到 401 才发现
        }
        return count
    }

    // MARK: - 风控降级链路（R1 缓解措施③：识别 → 唤起人工 → 自动重放）

    func presentVerification(_ challenge: PunishChallenge) async throws {
        state = .punished
        Logger.log(domain: .channel)
            .error("punished: kind=\(challenge.kind.rawValue, privacy: .public) status=\(challenge.statusCode ?? -1, privacy: .public)")
        // 唤起**可见** WebView 让人过滑块：把 1×1 宿主临时放大并加载挑战地址。
        // M1 会换成独立的全屏验证页（带取消/重试），spike 阶段先证明"能唤起、能恢复"。
        host.makeVisible(challenge.url)
        NotificationCenter.default.post(name: Signal.punishChallenge, object: challenge)
    }

    /// 人工验证完成后由 UI 调用：恢复离屏形态，等待中的请求在 `waitUntilReady()` 上自动续跑（即"自动重放"）
    func resumeAfterVerification() {
        host.makeHidden()
        state = .idle
        Logger.log(domain: .channel).info("verification finished, channel rearming")
        NotificationCenter.default.post(name: Signal.verificationFinished, object: nil)
    }

    private func handlePunishedIfNeeded(_ error: APIError) {
        guard case .punished(let challenge) = error else { return }
        Task { @MainActor [weak self] in try? await self?.presentVerification(challenge) }
    }

    /// 风控期间不丢请求，改为等待人工验证结果（有超时上限，避免 UI 不接管时永久吊住）
    private func waitUntilReady() async throws {
        let deadline = policy.timeoutNanos
        var waited: Int64 = 0
        while state == .punished {
            try await clock.sleep(nanos: policy.pollNanos)
            waited += policy.pollNanos
            if waited > deadline {
                throw APIError.punished(PunishChallenge(
                    url: ChannelWebViewHost.channelURL,
                    statusCode: 432,
                    kind: .unknown))
            }
        }
    }

    // MARK: - 闸门 + 重试（§5「限流 actor + 超时/重试」；§8.1 单测覆盖对象）

    private func gated<T>(_ run: () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            try await waitUntilReady()
            try await limiter.acquire()
            do {
                let value = try await run()
                await limiter.release()
                return value
            } catch {
                await limiter.release()
                let api = error as? APIError
                let canRetry = (attempt < policy.maxAttempts) && (api?.isRetryable ?? false)
                guard canRetry else { throw error }
                Logger.log(domain: .channel).warning("retry \(attempt, privacy: .public) after backoff")
                try await clock.sleep(nanos: policy.backoffNanos(afterFailedAttempt: attempt))
                attempt += 1
            }
        }
    }
}

// MARK: - 请求组装（纯函数，无实例状态；移出主类体，让 WebViewChannelLive 聚焦生命周期与双车道）

extension WebViewChannelLive {
    /// 请求签名：限流与去重都用它（顺序无关，保证同参同键）
    /// `nonisolated`：纯函数，单测可直接调用（`EndpointRegistryTests`）
    nonisolated static func signature(of request: WebChannelRequest) -> String {
        let queryString = request.query.sorted { $0.key < $1.key }.map { "\($0)=\($1)" }.joined(separator: "&")
        let formString = request.form.sorted { $0.key < $1.key }.map { "\($0)=\($1)" }.joined(separator: "&")
        return "\(request.method.rawValue) \(request.url.absoluteString)?\(queryString)#\(formString)"
    }

    /// Web 端 ajax 需要的头：Referer/Origin 是服务端校验项（R7 判据④）
    static func headers(for request: WebChannelRequest) -> [String: String] {
        var headers = ["Accept": "application/json, text/plain, */*",
                       "X-Requested-With": "XMLHttpRequest"]
        if let referer = request.headers["Referer"] {
            headers["Referer"] = referer
        }
        if let origin = request.headers["Origin"] {
            headers["Origin"] = origin
        }
        for (key, value) in request.headers where key != "Referer" && key != "Origin" {
            headers[key] = value
        }
        return headers
    }

    static func absolute(_ url: URL, query: [String: String]) -> URL {
        guard !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        items.append(contentsOf: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
        components.queryItems = items
        return components.url ?? url
    }

    static func formEncoded(_ fields: [String: String]) -> String {
        fields.sorted { $0.key < $1.key }
            .map { "\(Self.escape($0.key))=\(Self.escape($0.value))" }
            .joined(separator: "&")
    }

    static func escape(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func multipartBody(_ parts: [NativeRequest.MultipartPart], boundary: String) -> [UInt8] {
        var body = [UInt8]()
        func write(_ text: String) {
            body.append(contentsOf: Array(text.utf8))
        }
        for part in parts {
            write("--\(boundary)\r\n")
            switch part.value {
            case .text(let value):
                write("Content-Disposition: form-data; name=\"\(part.field)\"\r\n\r\n\(value)\r\n")
            case .file(let name, let mimeType, let data):
                write("Content-Disposition: form-data; name=\"\(part.field)\"; filename=\"\(name)\"\r\n")
                write("Content-Type: \(mimeType)\r\n\r\n")
                body.append(contentsOf: [UInt8](data))
                write("\r\n")
            }
        }
        write("--\(boundary)--\r\n")
        return body
    }

    static func nativeDefaults(adding headers: [String: String]) -> [String: String] {
        var merged = ["Accept": "application/json, text/plain, */*",
                      "Origin": "https://weibo.com"]
        for (key, value) in headers {
            merged[key] = value
        }
        return merged
    }
}

/// JS 侧收到的请求描述（字段名与 `ChannelScript.bootstrap` 里的 `req` 对齐）
private struct PageFetchRequest: Encodable {
    var id: String
    var url: String
    var method: String
    var headers: [String: String]
    var body: String?
}

/// 动态 key（用于兼容多种探测端点口径）
struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ string: String) {
        stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
