import XCTest
@testable import ZhiWei

/// 时间线缓存落地（PLAN §M2「节流与缓存落地」+ §8.1「Repository 层单测」）
///
/// 用 `FakeWebViewChannel` + `InMemoryKVStore` + 注入时钟，全程不碰真微博、不真等 TTL，
/// 覆盖 R1 的核心诉求：**staleTime 内不打服务器、回源失败优先回退过期缓存**。
@MainActor
final class TimelineCacheTests: XCTestCase {
    private static let home = APIWebEndpoint.homeTimelineFallback

    /// 可推进的虚拟时钟容器（TimelineCache 的 now 与 stale 判定共用一条时间线）。
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_700_000_000)

        func advance(_ seconds: TimeInterval) {
            date.addTimeInterval(seconds)
        }
    }

    private struct Harness {
        var provider: WebTimelineProvider
        var channel: FakeWebViewChannel
        var cache: TimelineCache
        var clock: Clock
    }

    private func harness(staleMilliseconds: Int = 180_000) throws -> Harness {
        let channel = try FakeWebViewChannel(responses: ["getIndex": Fixtures.data(named: "timeline.home")])
        let clock = Clock()
        let cache = TimelineCache(store: InMemoryKVStore(), now: { clock.date })
        let provider = WebTimelineProvider(
            channel: channel,
            cache: cache,
            staleMilliseconds: { staleMilliseconds })
        return Harness(provider: provider, channel: channel, cache: cache, clock: clock)
    }

    func testFreshWindowHitsCacheAndSkipsNetwork() async throws {
        let box = try harness()
        let first = try await box.provider.loadPage(after: .first)
        XCTAssertEqual(box.channel.fetchLog.count, 1)

        box.clock.advance(60) // 仍在 3 分钟新鲜窗内
        let second = try await box.provider.loadPage(after: .first)
        XCTAssertEqual(box.channel.fetchLog.count, 1, "staleTime 内绝不能再打服务器（R1 低调优先）")
        XCTAssertEqual(first.items.map(\.id), second.items.map(\.id), "命中缓存应回放同一页")
    }

    func testStaleWindowRefetchesAndRefreshesCache() async throws {
        let box = try harness(staleMilliseconds: 60000)
        _ = try await box.provider.loadPage(after: .first)
        box.clock.advance(61) // 越过新鲜窗
        _ = try await box.provider.loadPage(after: .first)
        XCTAssertEqual(box.channel.fetchLog.count, 2, "过期后应重新回源")
    }

    func testRiskErrorFallsBackToStaleCache() async throws {
        let box = try harness(staleMilliseconds: 1000)
        let ok = try await box.provider.loadPage(after: .first)
        box.clock.advance(60) // 先让它过期，迫使走回源
        box.channel.errors = ["getIndex": .rateLimited(retryAfterMilliseconds: nil)]

        let recovered = try await box.provider.loadPage(after: .first)
        XCTAssertEqual(recovered.items.count, ok.items.count, "回源被限频时回退过期缓存，不清屏不报错")
    }

    func testDecodeRegressionFallsBackToStaleCache() async throws {
        let box = try harness(staleMilliseconds: 1000)
        let ok = try await box.provider.loadPage(after: .first)
        box.clock.advance(60)
        // 状态 200 但内容解不出 → .decode，同样应回退过期缓存
        box.channel.responses = ["getIndex": Data("<html>改版了</html>".utf8)]

        let recovered = try await box.provider.loadPage(after: .first)
        XCTAssertEqual(recovered.items.count, ok.items.count, "改版导致解码失败时，过期缓存仍能撑起 UI")
    }

    func testRiskErrorWithoutCachePropagates() async throws {
        let challenge = try PunishChallenge(
            url: XCTUnwrap(URL(string: "https://m.weibo.cn/")),
            statusCode: 432,
            kind: .slider)
        let channel = FakeWebViewChannel(errors: ["getIndex": .punished(challenge)])
        let provider = WebTimelineProvider(channel: channel, cache: TimelineCache(store: InMemoryKVStore()))
        do {
            _ = try await provider.loadPage(after: .first)
            XCTFail("无任何缓存时，风控错误必须照抛以驱动降级链路")
        } catch let error as APIError {
            guard case .punished = error else { return XCTFail("应为 .punished，实际 \(String(describing: error))") }
        }
    }

    func testNotLoggedInNeverServedFromCache() async throws {
        let box = try harness(staleMilliseconds: 1000)
        _ = try await box.provider.loadPage(after: .first)
        box.clock.advance(60)
        box.channel.errors = ["getIndex": .notLoggedIn]
        do {
            _ = try await box.provider.loadPage(after: .first)
            XCTFail("未登录要引导重登（R2），不能用旧数据遮羞")
        } catch let error as APIError {
            guard case .notLoggedIn = error else { return XCTFail("应为 .notLoggedIn") }
        }
    }

    func testPurgeClearsMemoryAndDisk() async throws {
        let box = try harness()
        _ = try await box.provider.loadPage(after: .first)
        box.cache.purge()
        let key = WebTimelineProvider.cacheKey(endpoint: Self.home, cursor: .first)
        XCTAssertNil(box.cache.anyPayload(forKey: key))

        // purge 后再遇风控错误，因无缓存可退，应直接抛出
        box.channel.errors = ["getIndex": .rateLimited(retryAfterMilliseconds: nil)]
        do {
            _ = try await box.provider.loadPage(after: .first)
            XCTFail("purge 后无缓存可退，限频错误应抛出")
        } catch let error as APIError {
            guard case .rateLimited = error else { return XCTFail("应为 .rateLimited，实际 \(String(describing: error))") }
        }
    }

    func testDiskSurvivesMemoryEviction() {
        let store = InMemoryKVStore()
        let cache = TimelineCache(store: store, now: Date.init, memoryCapacity: 1, diskCapacity: 4)
        let payload = Data(#"{"ok":1,"data":{"list":[]}}"#.utf8)
        for page in 1 ... 3 {
            let cursor = WebCursor(maxID: "m\(page)", sinceID: nil, page: page, containerId: nil, seenCount: 0)
            cache.save(payload, forKey: WebTimelineProvider.cacheKey(endpoint: Self.home, cursor: cursor))
        }
        // 内存层只留最后一页，前两页仍应从磁盘读回（冷启动 / 回源失败兜底的前提）
        let firstCursor = WebCursor(maxID: "m1", sinceID: nil, page: 1, containerId: nil, seenCount: 0)
        let firstKey = WebTimelineProvider.cacheKey(endpoint: Self.home, cursor: firstCursor)
        XCTAssertNotNil(cache.anyPayload(forKey: firstKey))
    }
}
