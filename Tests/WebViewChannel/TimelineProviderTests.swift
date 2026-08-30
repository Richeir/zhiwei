import XCTest
@testable import ZhiWei

/// 时间线仓储 + 假通道（PLAN §8.1「Mock：以 `WebViewChannel` 协议为注入边界做 fake」）
///
/// 这条链覆盖：端点组装 → 车道请求 → 宽松解码 → 游标推进 → 未登录态迁移。
/// 全程不碰微博服务器，CI 可在无账号无网络环境跑（§8.2）。
@MainActor
final class TimelineProviderTests: XCTestCase {
    private func provider(_ fixture: String) throws -> (WebTimelineProvider, FakeWebViewChannel) {
        let fake = try FakeWebViewChannel(responses: [
            "getIndex": Fixtures.data(named: fixture)
        ])
        return (WebTimelineProvider(channel: fake), fake)
    }

    func testFirstPageDecodesAndAdvancesCursor() async throws {
        let (provider, fake) = try provider("timeline.home")
        let page = try await provider.loadPage(after: .first)

        XCTAssertEqual(page.items.count, 3)
        XCTAssertEqual(page.nextMaxID, "1725000000000")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(fake.fetchLog.count, 1)
        XCTAssertEqual(
            fake.fetchLog.first?.url.path,
            "/api/container/getIndex",
            "请求必须来自端点注册表，不许手拼 URL")

        let cursor = WebCursor.first.advancing(with: page)
        XCTAssertEqual(cursor.maxID, "1725000000000")
        XCTAssertEqual(cursor.seenCount, 3)
    }

    func testProbeSendsNoCursorOnFirstPage() async throws {
        let (provider, fake) = try provider("timeline.home")
        _ = try await provider.loadPage(after: .first)
        XCTAssertTrue(fake.fetchLog.first?.query.isEmpty ?? false, "首帧不该带 max_id/page")
    }

    func testNotLoggedInMapsToSessionState() async {
        let fake = FakeWebViewChannel(errors: ["getIndex": .notLoggedIn])
        let model = TimelineModel()
        await model.load(provider: WebTimelineProvider(channel: fake))
        XCTAssertEqual(model.phase, .signedOut)
        XCTAssertTrue(model.statuses.isEmpty)
    }

    func testFailureKeepsExistingContent() async throws {
        let ok = try FakeWebViewChannel(responses: ["getIndex": Fixtures.data(named: "timeline.home")])
        let model = TimelineModel()
        await model.load(provider: WebTimelineProvider(channel: ok))
        XCTAssertEqual(model.statuses.count, 3)

        // 第二页坏掉：已展示的内容必须留着（R1：可用性优先于新鲜度）
        let broken = FakeWebViewChannel(errors: ["getIndex": .timeout])
        await model.load(provider: WebTimelineProvider(channel: broken), more: true)
        XCTAssertEqual(model.statuses.count, 3, "分页失败不许清屏")
    }

    func testIdenticalRequestsShareOneSignature() async throws {
        let fake = try FakeWebViewChannel(responses: ["getIndex": Fixtures.data(named: "timeline.home")])
        let provider = WebTimelineProvider(channel: fake)
        _ = try await provider.loadPage(after: .first)
        _ = try await provider.loadPage(after: .first)

        // 去重发生在 `WebViewChannelLive`（真通道），假通道这边守的是前提：
        // 同参数请求必须算出同一签名——签名不稳定，`InFlightDeduper` 就永远命中不了。
        XCTAssertEqual(fake.duplicateCount, 1, "签名识别失效会让重复请求白烧风控预算")
    }

    func testDecodeFailureNamesTheEndpoint() async throws {
        let fake = FakeWebViewChannel(responses: ["getIndex": Data("<html>改版了</html>".utf8)])
        do {
            _ = try await WebTimelineProvider(channel: fake).loadPage(after: .first)
            XCTFail("应当解码失败")
        } catch let error as APIError {
            guard case .decode(let field, _) = error else { return XCTFail("应为 .decode，实际 \(String(describing: error))") }
            XCTAssertEqual(field, APIWebEndpoint.homeTimelineFallback.key, "错误要指到端点 key，改版时才知道动哪个文件")
        }
    }
}
