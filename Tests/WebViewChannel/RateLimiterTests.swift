import XCTest
@testable import ZhiWei

/// 限流 actor 单测（PLAN §8.1「限流 actor（间隔/并发/退避/去重）」）
///
/// 用 `VirtualMonotonicClock` 让"间隔 ≥1s"的断言在毫秒级完成，而不是真睡 3 秒。
final class RateLimiterTests: XCTestCase {
    func testDefaultPolicyMatchesTheNonNegotiableNumbers() {
        // 这两个数字写进过 README 的免责声明，改它们要连文档一起改
        XCTAssertEqual(RateLimitPolicy.standard.minimumIntervalNanos, 1_000_000_000)
        XCTAssertEqual(RateLimitPolicy.standard.maxConcurrency, 2)
    }

    func testIntervalGateSerializesAdmissions() async throws {
        let clock = VirtualMonotonicClock()
        let limiter = RateLimiter(policy: .standard, clock: clock)

        for _ in 0 ..< 4 {
            try await limiter.acquire()
            await limiter.release()
        }
        let snapshot = await limiter.snapshot
        XCTAssertEqual(snapshot.admissions, 4)
        // 三次"等待间隔"至少各睡过 1s 的虚拟时间（首次不需要等）
        let slept = await clock.totalSleptNanos
        XCTAssertGreaterThanOrEqual(
            slept,
            3 * 1_000_000_000 - 2 * 20_000_000,
            "允许轮粒度的误差，但不许小于 3 个间隔")
    }

    func testConcurrencyCapIsTwo() async {
        let clock = VirtualMonotonicClock()
        let limiter = RateLimiter(policy: .standard, clock: clock)

        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    try await limiter.acquire()
                    // 占住槽位，逼后面的请求排队
                    try await clock.sleep(nanos: 5_000_000)
                    await limiter.release()
                }
            }
            try? await group.waitForAll()
        }
        let snapshot = await limiter.snapshot
        XCTAssertLessThanOrEqual(snapshot.peakConcurrency, 2, "并发上限被突破 = R1 缓解措施失效")
        XCTAssertEqual(snapshot.admissions, 8)
    }

    func testBackoffGrowsExponentiallyButCaps() {
        let policy = RateLimitPolicy.standard
        XCTAssertEqual(policy.backoffNanos(afterFailedAttempt: 1), policy.backoffBaseNanos)
        XCTAssertEqual(policy.backoffNanos(afterFailedAttempt: 3), policy.backoffBaseNanos * 4)
        XCTAssertEqual(policy.backoffNanos(afterFailedAttempt: 99), policy.backoffBaseNanos * 64, "退避封顶 64 倍")
    }

    @MainActor
    func testPunishedErrorsAreNeverRetried() {
        // 风控后继续猛重试是最容易把账号打死的行为，必须在类型层就断掉
        XCTAssertFalse(APIError.punished(PunishChallenge(url: ChannelWebViewHost.channelURL, statusCode: 432, kind: .slider)).isRetryable)
        XCTAssertFalse(APIError.notLoggedIn.isRetryable)
        XCTAssertTrue(APIError.timeout.isRetryable)
        XCTAssertTrue(APIError.httpStatus(503).isRetryable)
        XCTAssertFalse(APIError.httpStatus(404).isRetryable)
    }

    func testCooldownPolicyIsStrictlySlower() {
        let standard = RateLimitPolicy.standard
        let cooldown = RateLimitPolicy.punishedCooldown
        XCTAssertGreaterThan(cooldown.minimumIntervalNanos, standard.minimumIntervalNanos)
        XCTAssertLessThan(cooldown.maxConcurrency, standard.maxConcurrency)
    }
}

/// 在途合并（§8.1「去重」）
final class InFlightDeduperTests: XCTestCase {
    func testSecondCallerReusesFirstResult() async throws {
        let deduper = InFlightDeduper()
        let payload = Data(#"{"ok":1}"#.utf8)

        // 第一个调用者成为 owner
        let first = try await deduper.join("key")
        XCTAssertNil(first, "首个调用者应当自己去取")

        let follower = Task { try await deduper.join("key") }
        try await Task.sleep(nanoseconds: 20_000_000)
        await deduper.publish("key", with: .success(payload))
        let followerGot = try await follower.value

        XCTAssertEqual(followerGot, payload, "跟随者应直接复用同一份回包")
        let counted = await deduper.coalescedCount
        XCTAssertEqual(counted, 1)
    }

    func testFailureIsBroadcastToFollowers() async throws {
        let deduper = InFlightDeduper()
        _ = try await deduper.join("k2")
        let follower = Task { () -> Bool in
            do { _ = try await deduper.join("k2")
                return false
            } catch { return true }
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        await deduper.publish("k2", with: .failure(APIError.timeout))
        let sawError = await follower.value
        XCTAssertTrue(sawError, "owner 失败时跟随者也要拿到失败，不能空等")

        // 桶已清空：后来的请求重新成为 owner
        let again = try await deduper.join("k2")
        XCTAssertNil(again)
    }
}
