import Foundation
import os

/// DI 组装根（PLAN §2.2）。全 App 只有这一处 `new` 依赖图；Feature 层只消费、不构造通道。
///
/// 红线（PLAN §5 / §7）：**任何网络出口都必须经 `channel`**。图片库、崩溃上报、
/// 未来的 WebSocket 都不例外——限流 actor 一旦能被绕过，R1 的缓解措施就形同虚设。
@MainActor
@Observable
final class AppContainer {
    let session: UserSession
    let channel: any WebViewChannel
    let store: any KVStore
    let crash: CrashReporting

    /// 会话检测用的轻量仓储（M1 起承担真实探测端点）
    let timeline: any TimelineProviding

    init(
        channel: any WebViewChannel,
        store: any KVStore,
        crash: CrashReporting = NoopCrashReporter(),
        session: UserSession? = nil,
        timeline: (any TimelineProviding)? = nil) {
        self.channel = channel
        self.store = store
        self.crash = crash
        self.session = session ?? UserSession()
        self.timeline = timeline ?? WebTimelineProvider(channel: channel)
    }

    /// 生产装配：双车道 WebViewChannel + UserDefaults 存储。
    static let live: AppContainer = {
        let defaults = KVDefaults()
        let channel = WebViewChannelLive()
        return AppContainer(channel: channel, store: defaults)
    }()

    /// 预览/测试装配：不发任何真实请求（PLAN §8.1「UI 测试不依赖真微博」）。
    static func fake(responses: [String: Data] = [:]) -> AppContainer {
        AppContainer(channel: FakeWebViewChannel(responses: responses), store: InMemoryKVStore())
    }
}
