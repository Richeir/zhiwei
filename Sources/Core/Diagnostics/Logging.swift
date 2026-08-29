import Foundation
import os

/// 日志按子系统分域（PLAN §5「日志 `os.Logger` 按子系统分域 + Sentry 占位」）。
///
/// 红线：**日志不得出现凭证**。所有走 `Logger` 的内容必须是开发者可读的诊断信息，
/// 任何 Cookie / SUB / XSRF-TOKEN / 手机号一律禁止入日志（`.private` 也只用于 PII，
/// 而凭证连 `.private` 都不该有——见 ` redact(_:)`）。
enum LogDomain: String, Sendable {
    case app
    case channel // WebViewChannel：双车道、限流、风控
    case api // APIWeb：端点、解码、契约
    case auth // 登录与会话（严禁记录 cookie 值）
    case timeline
    case compose
    case store
    case ui

    static let subsystem = "dev.zhiwei.app"
}

extension Logger {
    // Swift 6 严格并发无法从 `cacheLock` 推断线程安全，显式声明 `nonisolated(unsafe)`；
    // 真实同步由下方 NSLock 保证（读写都在锁内）。
    private nonisolated(unsafe) static var caches: [LogDomain: Logger] = [:]
    private static let cacheLock = NSLock()

    /// 取（并缓存）某域的 logger。
    /// `os.Logger` 本身是值类型且廉价，缓存只为避免重复构造与拼字符串。
    static func log(domain: LogDomain) -> Logger {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let hit = caches[domain] {
            return hit
        }
        let created = Logger(subsystem: LogDomain.subsystem, category: domain.rawValue)
        caches[domain] = created
        return created
    }

    /// 凭证脱敏：任何"看起来像 token"的字符串过这里再进日志。
    static func redact(_ value: String, keep head: Int = 3) -> String {
        guard value.count > head else { return "***" }
        return value.prefix(head) + "…(\(value.count))"
    }
}

/// 崩溃与日志上报的占位边界（PLAN §5 Sentry 占位、§7「遵守日志不含凭证红线」）。
///
/// M0 不引入 Sentry SDK（避免无 DSN 的包体与网络出口）；拿到 DSN 后在 project.yml 里
/// 打开 `sentry-cocoa` 依赖并提供 `SentryCrashReporter`，业务层零改动。
protocol CrashReporting: Sendable {
    func start(launchOptions: [String: Any]) async
    func record(_ error: Error, context: [String: String]) async
}

struct NoopCrashReporter: CrashReporting {
    func start(launchOptions _: [String: Any]) async {}
    func record(_ error: Error, context _: [String: String]) async {
        Logger.log(domain: .app).error("record error: \(String(describing: error), privacy: .public)")
    }
}
