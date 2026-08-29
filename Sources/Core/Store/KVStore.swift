import Foundation
import os

// MARK: - KV 存储（PLAN §2.2 `Core/Store`：偏好/草稿/搜索历史）
//
// 凭证红线（§5 / R2）：**登录凭证永不落 App 存储**。Cookie 只存在于系统 WebKit CookieJar，
// 本层连"顺手缓存一下 token"都不允许——所以这里内置一道拒绝闸（`CredentialGuard`），
// 任何看起来像凭证的 key 直接拒写并打日志（日志只写 key 名，不写值）。

/// 存储键：登记在此，避免各处散落字符串键。
struct StoreKey: Hashable, Sendable, CustomStringConvertible {
    var rawName: String
    var description: String {
        rawName
    }

    init(_ rawName: String) {
        self.rawName = rawName
    }

    // 偏好
    static let timelineStaleMilliseconds = StoreKey("pref.timeline.staleMs")
    static let lastSeenTimelineCursor = StoreKey("pref.timeline.cursor")
    static let reduceMotionOverride = StoreKey("pref.ui.reduceMotion")
    /// R7 spike 结论留档（M0 出口条件要写进 docs/VERSIONS.md 的东西）
    static let r7SpikeLastResult = StoreKey("debug.r7.spikeResult")

    /// 搜索历史与账号标识
    static let searchHistory = StoreKey("search.history")
    /// 上次登录成功的 uid（**只是标识，不是凭证**，用于"当前账号"占位展示）
    static let lastSignedInUID = StoreKey("account.lastUID")

    /// 草稿列表（整体存一个数组：草稿量级很小，拆开存只会增加枚举键的复杂度）
    static let draftList = StoreKey("draft.list")

    static func prefixed(_ scope: String, _ name: String) -> StoreKey {
        StoreKey("\(scope).\(name)")
    }
}

/// 凭证形态的键名一律拒写。判定故意宽松——误拒最多让人改个键名，漏拒则踩红线。
enum CredentialGuard {
    private static let bannedSubstrings = ["cookie", "sub", "xsrf", "token", "password", "passwd", "ticket", "sso", "auth"]

    static func looksLikeCredential(_ key: StoreKey) -> Bool {
        let name = key.rawName.lowercased()
        return bannedSubstrings.contains { name.contains($0) }
    }
}

/// KV 读写边界（协议化以便测试用 `InMemoryKVStore`）
protocol KVStore: AnyObject {
    func string(_ key: StoreKey) -> String?
    func setString(_ value: String?, for key: StoreKey)
    func data(_ key: StoreKey) -> Data?
    func setData(_ data: Data?, for key: StoreKey)
    func int(_ key: StoreKey) -> Int?
    func setInt(_ value: Int?, for key: StoreKey)
    func removeAll(in scope: String)
}

extension KVStore {
    func codable<T: Codable>(_ type: T.Type, for key: StoreKey) -> T? {
        guard let raw = data(key) else { return nil }
        return try? JSONDecoder().decode(type, from: raw)
    }

    /// 返回是否真的写入（被凭证闸拦下时 false，调用方应视为编程错误）
    @discardableResult
    func setCodable<T: Codable>(_ value: T?, for key: StoreKey) -> Bool {
        guard !CredentialGuard.looksLikeCredential(key) else {
            Logger.log(domain: .store).error("拒绝写入疑似凭证键：\(key.rawName, privacy: .public)")
            return false
        }
        guard let value else { setData(nil, for: key)
            return true
        }
        guard let raw = try? JSONEncoder().encode(value) else { return false }
        setData(raw, for: key)
        return true
    }
}

/// 生产实现：UserDefaults 独立 suite（不污染标准域，卸载时好清）
final class KVDefaults: KVStore {
    private let defaults: UserDefaults

    init(suiteName: String = "dev.zhiwei.app.store") {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func string(_ key: StoreKey) -> String? {
        defaults.string(forKey: key.rawName)
    }

    func setString(_ value: String?, for key: StoreKey) {
        guard !CredentialGuard.looksLikeCredential(key) else {
            Logger.log(domain: .store).error("拒绝写入疑似凭证键：\(key.rawName, privacy: .public)")
            return
        }
        defaults.set(value, forKey: key.rawName)
    }

    func data(_ key: StoreKey) -> Data? {
        defaults.data(forKey: key.rawName)
    }

    func setData(_ data: Data?, for key: StoreKey) {
        guard !CredentialGuard.looksLikeCredential(key) else {
            Logger.log(domain: .store).error("拒绝写入疑似凭证键：\(key.rawName, privacy: .public)")
            return
        }
        defaults.set(data, forKey: key.rawName)
    }

    func int(_ key: StoreKey) -> Int? {
        defaults.object(forKey: key.rawName) == nil ? nil : defaults.integer(forKey: key.rawName)
    }

    func setInt(_ value: Int?, for key: StoreKey) {
        guard !CredentialGuard.looksLikeCredential(key) else { return }
        defaults.set(value, forKey: key.rawName)
    }

    func removeAll(in scope: String) {
        for name in defaults.dictionaryRepresentation().keys where name.hasPrefix("\(scope).") {
            defaults.removeObject(forKey: name)
        }
    }
}

/// 测试/预览实现
final class InMemoryKVStore: KVStore {
    private var storage: [String: Data] = [:]
    private var strings: [String: String] = [:]
    private var ints: [String: Int] = [:]

    func string(_ key: StoreKey) -> String? {
        strings[key.rawName]
    }

    func setString(_ value: String?, for key: StoreKey) {
        strings[key.rawName] = value
    }

    func data(_ key: StoreKey) -> Data? {
        storage[key.rawName]
    }

    func setData(_ data: Data?, for key: StoreKey) {
        storage[key.rawName] = data
    }

    func int(_ key: StoreKey) -> Int? {
        ints[key.rawName]
    }

    func setInt(_ value: Int?, for key: StoreKey) {
        ints[key.rawName] = value
    }

    func removeAll(in scope: String) {
        storage = storage.filter { !$0.key.hasPrefix("\(scope).") }
        strings = strings.filter { !$0.key.hasPrefix("\(scope).") }
        ints = ints.filter { !$0.key.hasPrefix("\(scope).") }
    }
}
