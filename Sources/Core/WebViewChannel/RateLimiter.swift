import Foundation

// MARK: - 限流与去重（PLAN §5「限流 actor：间隔 ≥1s、并发 ≤2，超时/重试」+ R1 缓解措施②）
//
// 这是 R1 唯一的技术性防线，也是**不可协商项**（AGENTS.md 硬约束）：
// 任何请求都要先过 `acquire()` 再发出，`release()` 只在请求真正结束后调用。
// Repository / Feature 层一律不得自行发请求。

/// 单调时钟抽象：把"等待"从限流逻辑里剥出来，让 §8.1 的间隔/退避单测可确定性运行（不必真睡 1s）。
protocol MonotonicClock: Sendable {
    func nowNanos() async -> Int64
    func sleep(nanos: Int64) async throws
}

/// 生产时钟：真实睡眠，走 `Task.sleep`（可被取消；取消即抛出，由通道层转成 `.cancelled`）
struct SystemMonotonicClock: MonotonicClock {
    func nowNanos() async -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds)
    }

    func sleep(nanos: Int64) async throws {
        guard nanos > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(nanos))
    }
}

/// 测试时钟：不真睡，只推进虚拟时间。这样"间隔 ≥1s"这类断言可以在毫秒级跑完。
actor VirtualMonotonicClock: MonotonicClock {
    private var nanos: Int64 = 0
    private(set) var totalSleptNanos: Int64 = 0

    func nowNanos() async -> Int64 {
        nanos
    }

    func sleep(nanos amount: Int64) async throws {
        try Task.checkCancellation()
        let delta = max(0, amount)
        nanos += delta
        totalSleptNanos += delta
        await Task.yield() // 让其他任务有机会交错，保证并发测试有意义
    }

    /// 手动推进虚拟时间
    func advance(_ amount: Int64) {
        nanos += amount
    }
}

/// 限流策略（默认值直接来自 PLAN R1 缓解措施②，改数值要同步改 PLAN）
struct RateLimitPolicy: Sendable, Equatable {
    /// 相邻两次请求的最小起始间隔（纳秒）。默认 1s
    var minimumIntervalNanos: Int64
    /// 同时在途请求上限。默认 2
    var maxConcurrency: Int
    /// 单次业务请求最多尝试次数（含首次）
    var maxAttempts: Int
    /// 退避基数（第 n 次失败后睡 base * 2^(n-1)）
    var backoffBaseNanos: Int64
    /// 单次请求的挂钟超时
    var timeoutNanos: Int64
    /// 闸门轮询粒度（见 `RateLimiter` 的实现取舍）
    var pollNanos: Int64

    static let standard = RateLimitPolicy(
        minimumIntervalNanos: 1_000_000_000,
        maxConcurrency: 2,
        maxAttempts: 3,
        backoffBaseNanos: 800_000_000,
        timeoutNanos: 12_000_000_000,
        pollNanos: 20_000_000)

    /// 更保守的档位：命中风控后临时降速（R1 缓解措施③的配套）
    static let punishedCooldown = RateLimitPolicy(
        minimumIntervalNanos: 3_000_000_000,
        maxConcurrency: 1,
        maxAttempts: 2,
        backoffBaseNanos: 2_000_000_000,
        timeoutNanos: 15_000_000_000,
        pollNanos: 50_000_000)

    func backoffNanos(afterFailedAttempt attempt: Int) -> Int64 {
        let capped = min(max(0, attempt - 1), 6) // 最多 64 倍，避免退避失控
        return backoffBaseNanos * (1 << capped)
    }
}

/// 发送闸门：**并发 ≤2 + 起始间隔 ≥1s**。
///
/// 实现取舍：用「虚拟/真实时钟 + 轮询」而不是 continuation 排队。
/// 理由：本场景相邻请求本来就间隔 1s 级，20ms 轮询的开销完全可忽略，
/// 换来的是零死锁面（取消、异常、actor 重入都不会把闸门卡住）；
/// 代价是极端情况下后来者可能插到前面——对一个刻意低调的客户端不构成问题。
/// 需要严格 FIFO 时（例如保证分页顺序）由调用方串行化，不在此处保证。
actor RateLimiter {
    private let policy: RateLimitPolicy
    private let clock: any MonotonicClock

    private var inflight = 0
    private var nextAllowedNanos: Int64 = 0

    /// 观测指标（供 R7 spike 面板与单测断言，不参与决策）
    private(set) var admissionCount = 0
    private(set) var peakConcurrency = 0

    init(policy: RateLimitPolicy = .standard, clock: any MonotonicClock = SystemMonotonicClock()) {
        self.policy = policy
        self.clock = clock
    }

    var currentPolicy: RateLimitPolicy {
        policy
    }

    var snapshot: Snapshot {
        Snapshot(inflight: inflight, admissions: admissionCount, peakConcurrency: peakConcurrency)
    }

    struct Snapshot: Sendable, Equatable {
        var inflight: Int
        var admissions: Int
        var peakConcurrency: Int
    }

    /// 取得一个发送许可：先等并发槽位，再等时间闸门到点。
    func acquire() async throws {
        while true {
            let now = await clock.nowNanos()
            if inflight < policy.maxConcurrency, now >= nextAllowedNanos {
                break
            }
            try await clock.sleep(nanos: policy.pollNanos)
        }
        inflight += 1
        peakConcurrency = max(peakConcurrency, inflight)
        nextAllowedNanos = await max(nextAllowedNanos, clock.nowNanos()) + policy.minimumIntervalNanos
        admissionCount += 1
    }

    /// 释放许可。请求真正结束（成功/失败/超时/取消）后必须调用，否则闸门会永久收紧。
    func release() {
        inflight = max(0, inflight - 1)
    }
}

// MARK: - 相同请求的在途合并（§8.1「去重」）

/// 同一 URL + 同一参数的请求在途时只发一次，后来者复用同一份回包。
///
/// 为什么值得做：时间线分页与下拉刷新容易撞车，重复请求只会白白消耗风控预算（R1）。
actor InFlightDeduper {
    private struct Bucket {
        var followers: [CheckedContinuation<Data, any Error>] = []
    }

    private var buckets: [String: Bucket] = [:]
    private(set) var coalescedCount = 0

    /// 返回 `nil` 表示"你是发起方，去取吧"；返回非 nil 表示"命中在途合并，直接用这份数据"。
    func join(_ key: String) async throws -> Data? {
        // 判空与登记之间没有 await 点，actor 保证这段是原子的（不会出现两个 owner）
        guard buckets[key] != nil else {
            buckets[key] = Bucket()
            return nil
        }
        coalescedCount += 1
        return try await withCheckedThrowingContinuation { cont in
            buckets[key]?.followers.append(cont)
        }
    }

    /// 发起方完成后发布结果（成功或失败都唤醒全部跟随者），并清空桶。
    func publish(_ key: String, with result: Result<Data, any Error>) {
        guard let bucket = buckets.removeValue(forKey: key) else { return }
        for cont in bucket.followers {
            cont.resume(with: result)
        }
    }
}
