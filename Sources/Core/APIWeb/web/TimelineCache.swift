import Foundation
import os

// MARK: - 会话级缓存的统一清理契约
//
// 登出 / 切号时一并清空，避免上一个账号的时间线（含内存层）跨账号残留（R2 + R1「不囤数据」）。
// 由 `UserSession.signOut()` 遍历调用。
@MainActor
protocol SessionScopedCache: AnyObject {
    func purge()
}

// MARK: - 时间线载荷缓存（PLAN §M2「Repository 层 staleTime + 磁盘缓存」/ R1「降低风控触发概率优先于数据新鲜度」）
//
// 取向与纪律：
//   · 缓存的是车道① 返回的**原始 JSON 载荷**，不是解码后的 `StatusPage`——把缓存与 DTO 字段
//     churn 解耦（改版只动 `Core/APIWeb`，缓存仍能回放），也与契约快照的「录原始回包」口径一致。
//   · 双层：内存（前台高频命中、零 IO）+ 磁盘（`KVStore`，供冷启动与回源失败兜底）。
//   · 容量刻意小（只覆盖首页与前几页）：本客户端要的是「少打服务器」，不是离线浏览器。
//   · 写盘走 `KVStore`，凭证红线由存储层 `CredentialGuard` 兜底；缓存键是端点 + 游标，不含任何 cookie。
@MainActor
final class TimelineCache: SessionScopedCache {
    /// 磁盘键 scope：登出时按此整片清除（`UserSession.signOut` → `purge`）。
    static let scope = "timeline.cache"
    private static let indexKey = StoreKey.prefixed(scope, "index")

    /// 缓存条目：落盘载荷 + 入库时刻（age 判定的依据）。
    private struct Entry: Codable {
        var savedAt: Date
        var payload: Data
    }

    private let store: any KVStore
    /// 可注入时钟：让 staleTime 过期判定可在单测里确定性地跑（不必真等 3 分钟）。
    private let now: () -> Date
    private let memoryCapacity: Int
    private let diskCapacity: Int

    /// 内存层与其 LRU 序（尾部为最近使用）。
    private var memory: [String: Entry] = [:]
    private var order: [String] = []

    init(
        store: any KVStore,
        now: @escaping () -> Date = Date.init,
        memoryCapacity: Int = 6,
        diskCapacity: Int = 12) {
        self.store = store
        self.now = now
        self.memoryCapacity = max(1, memoryCapacity)
        self.diskCapacity = max(memoryCapacity, diskCapacity)
    }

    /// staleTime 内命中：返回原始载荷；过期 / 缺失 → `nil`（调用方据此回源）。
    /// `staleMilliseconds <= 0` 视为「不信任缓存」，恒 `nil`。
    func freshPayload(forKey key: String, staleMilliseconds: Int) -> Data? {
        guard staleMilliseconds > 0, let entry = entry(forKey: key) else { return nil }
        let ageMilliseconds = now().timeIntervalSince(entry.savedAt) * 1000
        return ageMilliseconds <= Double(staleMilliseconds) ? entry.payload : nil
    }

    /// 不看新鲜度的载荷（用于回源失败时回退到过期缓存）。
    func anyPayload(forKey key: String) -> Data? {
        entry(forKey: key)?.payload
    }

    /// 回源成功后写缓存（内存 + 磁盘，各自按容量做 LRU 淘汰）。
    func save(_ payload: Data, forKey key: String) {
        let entry = Entry(savedAt: now(), payload: payload)
        memory[key] = entry
        touch(key)
        evictMemoryIfNeeded()
        persist(key, entry: entry)
        evictDiskIfNeeded()
    }

    /// 清空（登出 / 切号）：内存与磁盘一并清，不留跨账号残渣。
    func purge() {
        memory.removeAll()
        order.removeAll()
        store.removeAll(in: Self.scope)
        Logger.log(domain: .store).info("timeline cache purged")
    }

    // MARK: - 私有

    private func entry(forKey key: String) -> Entry? {
        if let hit = memory[key] {
            touch(key)
            return hit
        }
        guard let loaded = store.codable(Entry.self, for: Self.diskKey(key)) else { return nil }
        memory[key] = loaded // 磁盘命中 → 提升到内存
        touch(key)
        return loaded
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func evictMemoryIfNeeded() {
        while order.count > memoryCapacity {
            let dropped = order.removeFirst()
            memory[dropped] = nil
        }
    }

    private func persist(_ key: String, entry: Entry) {
        guard store.setCodable(entry, for: Self.diskKey(key)) else {
            Logger.log(domain: .store).error("时间线缓存写盘被拒：\(key.prefix(48), privacy: .public)")
            return
        }
        var index = store.codable([String: Date].self, for: Self.indexKey) ?? [:]
        index[key] = entry.savedAt
        store.setCodable(index, for: Self.indexKey)
    }

    private func evictDiskIfNeeded() {
        guard var index = store.codable([String: Date].self, for: Self.indexKey), index.count > diskCapacity else { return }
        let dropCount = index.count - diskCapacity
        for (key, _) in index.sorted(by: { $0.value < $1.value }).prefix(dropCount) {
            index[key] = nil
            store.setCodable(nil as Data?, for: Self.diskKey(key))
            memory[key] = nil
            order.removeAll { $0 == key }
        }
        store.setCodable(index, for: Self.indexKey)
    }

    private static func diskKey(_ key: String) -> StoreKey {
        StoreKey.prefixed(scope, key)
    }
}
