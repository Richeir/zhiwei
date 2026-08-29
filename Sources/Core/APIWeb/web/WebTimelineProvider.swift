import Foundation

// MARK: - 时间线仓储（PLAN D6：Repository 层；后端抽象的 `web/` 默认实现）

/// 时间线读取边界。UI/ViewModel 只认这个协议，不认 Web 端点。
@MainActor
protocol TimelineProviding {
    func loadPage(after cursor: WebCursor) async throws -> StatusPage
}

/// Web 车道实现：端点 → 车道① → 宽松解码 → `StatusPage`。
///
/// M2 会在这里挂 staleTime + 磁盘缓存（§M2「缓存落地」）与 m 站兜底切换；
/// M0 只需证明"端点注册表 → 通道 → DTO"这条链在结构上是通的。
@MainActor
struct WebTimelineProvider: TimelineProviding {
    let channel: any WebViewChannel
    var endpoint: APIWebEndpoint = .homeTimeline

    func loadPage(after cursor: WebCursor) async throws -> StatusPage {
        let request = WebChannelRequest(
            url: endpoint.url,
            method: endpoint.method,
            query: cursor.queryItems(),
            headers: endpoint.requestHeaders())
        let data = try await channel.fetch(request)
        let payload: TimelinePayload
        do {
            payload = try JSONDecoder().decode(TimelinePayload.self, from: data)
        } catch {
            // 解码失败 = 改版的第一现场。field 用端点 key 定位，hint 只带错误类型；
            // URL 与 cookie 一律不进错误对象（凭证红线）
            throw APIError.decode(field: endpoint.key, hint: String(describing: type(of: error)))
        }
        return payload.asPage()
    }
}

/// 两种时间线回包口径的合并解码（weibo.com `data.list` / m 站 `data.cards[].mblog`）
struct TimelinePayload: Decodable, Sendable {
    var statuses: [WBStatus]
    var nextMaxID: String?
    var pageNumber: Int?
    var hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case data, list, statuses, cards
        case maxID = "max_id"
        case page
        case cardlistInfo
        case haveMore = "have_more"
    }

    init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        var payload = root
        if let inner = try? root.nestedContainer(keyedBy: CodingKeys.self, forKey: .data) {
            payload = inner
        }

        var items = (try? payload.decode([WBStatus].self, forKey: .list))
            ?? (try? payload.decode([WBStatus].self, forKey: .statuses))
            ?? []
        if items.isEmpty {
            let cards = (try? payload.decode([Card].self, forKey: .cards)) ?? []
            items = cards.compactMap(\.mblog)
        }
        statuses = items
        nextMaxID = payload.zwString(.maxID) ?? TimelinePayload.maxID(from: payload)
        pageNumber = payload.zwOptionalInt(.page)
        hasMore = (payload.zwOptionalInt(.haveMore) ?? 1) == 1
    }

    /// m 站的游标有时藏在 `cardlistInfo` 里，兜一下（实测后收敛）
    private static func maxID(from container: KeyedDecodingContainer<CodingKeys>) -> String? {
        guard let info = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .cardlistInfo) else { return nil }
        return info.zwString(.maxID)
    }

    func asPage() -> StatusPage {
        StatusPage(items: statuses, nextMaxID: nextMaxID, pageNumber: pageNumber, hasMore: hasMore)
    }

    struct Card: Decodable, Sendable {
        var mblog: WBStatus?
        var cardStyle: Int?
        private enum Keys: String, CodingKey { case mblog, cardStyle = "card_style" }
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            mblog = try? container.decode(WBStatus.self, forKey: .mblog)
            cardStyle = container.zwOptionalInt(.cardStyle)
        }
    }
}
