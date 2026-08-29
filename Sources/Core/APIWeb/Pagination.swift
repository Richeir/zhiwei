import Foundation

// MARK: - 分页游标（PLAN §2.2「分页游标」/ §D6「分页/缓存/游标自研薄层」）
//
// Web 端两套口径混着用，所以游标是"多字段可选"的容器而不是单个 page 数字：
//   · weibo.com ajax：`max_id` / `since_id`（字符串化的时间片 ID）
//   · m.weibo.cn container：`containerid` + `page`
// 游标推进与"是否还有下一页"的判定都收敛在这里，Repository 只消费结果。

struct WebCursor: Sendable, Equatable {
    /// weibo.com 系：上一页最后一条的 `common_page_cursor` / `max_id`
    var maxID: String?
    /// 增量拉取用（下拉刷新时只看新内容）
    var sinceID: String?
    /// m 站 container 系页码（从 1 起）
    var page: Int
    /// m 站 `containerid`（如 102803 + 某人的微博列表）；有值时优先于 page 语义
    var containerId: String?
    /// 已见 ID 集合的大小，用于检测"游标不动了"（Web 端到底还会重复回同一页）
    var seenCount: Int

    static let first = WebCursor(maxID: nil, sinceID: nil, page: 1, containerId: nil, seenCount: 0)

    var isFirstChild: Bool {
        page == 1 && maxID == nil
    }

    /// 组装成请求 query。字段名以 Web 端实测为准（改版只动这里）。
    func queryItems() -> [String: String] {
        var items: [String: String] = [:]
        if let maxID, !maxID.isEmpty {
            items["max_id"] = maxID
        }
        if let sinceID, !sinceID.isEmpty {
            items["since_id"] = sinceID
        }
        if page > 1 {
            items["page"] = String(page)
        }
        if let containerId {
            items["containerid"] = containerId
        }
        return items
    }

    /// 用本页结果推进游标。
    ///
    /// 关键防御：如果 `max_id` 没变且本页 ID 全部已见，视为到底（`hasMore == false`），
    /// 否则无限滚动能把限流预算全烧在同一页上（R1）。
    func advancing(with page: StatusPage) -> WebCursor {
        var next = self
        next.maxID = page.nextMaxID ?? maxID
        if page.nextMaxID == nil {
            next.page = page.pageNumber ?? (self.page + 1)
        }
        next.seenCount = seenCount + page.items.count
        return next
    }
}

/// 一页时间线结果
struct StatusPage: Sendable, Equatable {
    var items: [WBStatus]
    /// 回包里的 `max_id`（两种口径都往这一个字段收）
    var nextMaxID: String?
    /// m 站回包的当前页码
    var pageNumber: Int?
    var hasMore: Bool

    init(items: [WBStatus], nextMaxID: String? = nil, pageNumber: Int? = nil, hasMore: Bool = true) {
        self.items = items
        self.nextMaxID = nextMaxID
        self.pageNumber = pageNumber
        self.hasMore = hasMore && !items.isEmpty
    }

    static let empty = StatusPage(items: [], nextMaxID: nil, pageNumber: nil, hasMore: false)
}
