import Foundation

// MARK: - 草稿 / 搜索历史 / 偏好（PLAN §2.2「Store：偏好/草稿/搜索历史 KV」，M3 发布编辑器与 M6 搜索直接用）

struct Draft: Codable, Equatable, Identifiable, Sendable {
    var id: Date {
        updatedAt
    }

    var text: String
    /// 已插入的话题名（不含 `#`）
    var topicNames: [String]
    var createdAt: Date
    var updatedAt: Date

    init(text: String, topicNames: [String] = [], now: Date = .now) {
        self.text = text
        self.topicNames = topicNames
        createdAt = now
        updatedAt = now
    }

    var isEmptyText: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 草稿箱。写盘时机由调用方决定（M3：编辑器失焦 / 退出时自动存）。
struct DraftStore {
    let store: any KVStore
    /// 上限刻意小：草稿是"接着写"的，不是笔记本（R1 低调，也不做数据囤积）
    static let capacity = 10

    func all() -> [Draft] {
        let drafts = store.codable([Draft].self, for: .draftList) ?? []
        return drafts.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 覆盖同文本的旧草稿，避免每次自动存都堆一条
    @discardableResult
    func save(_ draft: Draft) -> Bool {
        var drafts = all()
        if let index = drafts.firstIndex(where: { $0.text == draft.text }) {
            drafts[index] = draft
        } else {
            drafts.insert(draft, at: 0)
        }
        if drafts.count > Self.capacity {
            drafts.removeLast(drafts.count - Self.capacity)
        }
        return store.setCodable(drafts, for: .draftList)
    }

    @discardableResult
    func delete(_ draft: Draft) -> Bool {
        let drafts = all().filter { $0 != draft }
        return store.setCodable(drafts, for: .draftList)
    }

    func clear() {
        store.setCodable([Draft](), for: .draftList)
    }
}

/// 搜索历史：LRU + 去重 + 截断（M6）
struct SearchHistoryStore {
    let store: any KVStore
    static let capacity = 20

    struct Record: Codable, Equatable, Sendable {
        var query: String
        var tab: String
        var at: Date
    }

    func recent(limit: Int = 10) -> [Record] {
        Array((store.codable([Record].self, for: .searchHistory) ?? []).prefix(limit))
    }

    func record(_ query: String, tab: SearchTab, at: Date = .now) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var records = store.codable([Record].self, for: .searchHistory) ?? []
        records.removeAll { $0.query == trimmed && $0.tab == tab.rawValue }
        records.insert(Record(query: trimmed, tab: tab.rawValue, at: at), at: 0)
        if records.count > Self.capacity {
            records.removeLast(records.count - Self.capacity)
        }
        store.setCodable(records, for: .searchHistory)
    }

    func clear() {
        store.setCodable([Record](), for: .searchHistory)
    }
}

/// 偏好项（含 §M2 的 staleTime 配置：新鲜度让位于低调）
enum Preferences {
    /// 时间线缓存视为新鲜的时长；默认 3 分钟（比"最新"更重要的是"少打服务器"）
    static let defaultStaleMilliseconds = 180_000

    static func timelineStale(_ store: any KVStore) -> Int {
        store.int(.timelineStaleMilliseconds) ?? defaultStaleMilliseconds
    }

    static func setTimelineStale(_ milliseconds: Int, store: any KVStore) {
        store.setInt(max(0, milliseconds), for: .timelineStaleMilliseconds)
    }
}
