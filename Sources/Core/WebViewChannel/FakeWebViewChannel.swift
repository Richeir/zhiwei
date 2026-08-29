import Foundation

// MARK: - 测试/预览用假通道（PLAN §8.1「以 `WebViewChannel` 协议为注入边界做 fake（回放 Web 端点契约 JSON），UI 测试不依赖真微博」）
//
// 有了这层注入边界，UI 与 Repository 的测试完全不碰微博服务器——这既是 R1 低调要求，
// 也让 CI 可以在没有账号、没有网络的情况下跑（§8.2 PR 门禁）。

@MainActor
final class FakeWebViewChannel: WebViewChannel {
    /// key = URL 片段（子串匹配，按插入顺序取首个命中）
    var responses: [String: Data]
    var errors: [String: APIError]
    /// 人为延迟，用来测 `.task(id:)` 竞态取消与骨架屏
    var latency: Duration = .zero
    /// 探针返回值
    var probe: SessionProbe

    private(set) var fetchLog: [WebChannelRequest] = []
    private(set) var nativeLog: [NativeRequest] = []
    private(set) var verificationRequests: [PunishChallenge] = []

    /// 限流合规性观测：同参数请求的重复次数（去重测试用）
    private(set) var duplicateCount = 0

    init(
        responses: [String: Data] = [:],
        errors: [String: APIError] = [:],
        probe: SessionProbe = SessionProbe(
            isLoggedIn: true,
            uid: "fake-uid",
            sawLoginCookies: true,
            elapsedMilliseconds: 1)) {
        self.responses = responses
        self.errors = errors
        self.probe = probe
    }

    /// 从 bundle 里的契约 JSON 装配（Tests/Fixtures 与 previews 共用）。
    /// 注意：App target 没有 `Bundle.module`，测试里显式传 `Bundle(for: …)`。
    static func fromFixtures(named names: [String], in bundle: Bundle = .main) -> FakeWebViewChannel {
        var map: [String: Data] = [:]
        for name in names {
            if let url = bundle.url(forResource: name, withExtension: "json"),
               let data = try? Data(contentsOf: url) {
                map[name] = data
            }
        }
        return FakeWebViewChannel(responses: map)
    }

    var state: ChannelState = .ready

    func fetch(_ request: WebChannelRequest) async throws -> Data {
        if latency > .zero {
            try? await Task.sleep(for: latency)
        }
        let signature = WebViewChannelLive.signature(of: request)
        if fetchLog.contains(where: { WebViewChannelLive.signature(of: $0) == signature }) {
            duplicateCount += 1
        }
        fetchLog.append(request)
        return try reply(for: request.url.absoluteString)
    }

    func sendNative(_ request: NativeRequest) async throws -> Data {
        if latency > .zero {
            try? await Task.sleep(for: latency)
        }
        nativeLog.append(request)
        return try reply(for: request.url.absoluteString)
    }

    func probeSession() async throws -> SessionProbe {
        if latency > .zero {
            try? await Task.sleep(for: latency)
        }
        return probe
    }

    func presentVerification(_ challenge: PunishChallenge) async throws {
        verificationRequests.append(challenge)
        state = .ready
    }

    private func reply(for urlString: String) throws -> Data {
        for (needle, error) in errors where urlString.contains(needle) {
            throw error
        }
        for (needle, data) in responses where urlString.contains(needle) {
            return data
        }
        throw APIError.business(code: 404, message: "fake channel 没有为 \(urlString) 配置回包")
    }
}
