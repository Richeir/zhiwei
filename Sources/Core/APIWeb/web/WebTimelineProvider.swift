import Foundation
import os

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
    /// 移动 UA 下 PC 站 weibo.com 会被 302 跳 m 站，车道① 与 m 站接口同源才能 fetch 成功，
    /// 故首页默认走 m 站 container 口径（homeTimelineFallback）。
    var endpoint: APIWebEndpoint = .homeTimelineFallback
    /// 载荷缓存（PLAN §M2）：`nil` 表示不缓存（M0 测试 / 预览用）。
    var cache: TimelineCache?
    /// 新鲜度窗口来源：设置页可改，默认读 `Preferences.timelineStale`（回写于 §R1「低调优先」）。
    var staleMilliseconds: () -> Int = { Preferences.defaultStaleMilliseconds }

    func loadPage(after cursor: WebCursor) async throws -> StatusPage {
        let key = Self.cacheKey(endpoint: endpoint, cursor: cursor)

        // 1. staleTime 内命中 → 直接回缓存，不打服务器（R1 的技术性收益就在这一步）
        if let cache, let fresh = cache.freshPayload(forKey: key, staleMilliseconds: staleMilliseconds()),
           let page = try? Self.decode(fresh, endpoint: endpoint) {
            Logger.log(domain: .timeline).debug("cache fresh hit: \(key.prefix(56), privacy: .public)")
            return page
        }

        let request = WebChannelRequest(
            url: endpoint.url,
            method: endpoint.method,
            query: cursor.queryItems(),
            headers: endpoint.requestHeaders())
        do {
            let data = try await channel.fetch(request)
            let page = try Self.decode(data, endpoint: endpoint)
            cache?.save(data, forKey: key)
            return page
        } catch {
            // 2. 回源失败且属风控/传输/改版类错误 → 回退过期缓存（可用性优先于新鲜度，R1）。
            //    `.notLoggedIn` / `.cancelled` 等不在其列：该引导重登、该取消，不能拿旧数据遮羞。
            if let cache, Self.canServeStale(error), let stale = cache.anyPayload(forKey: key),
               let page = try? Self.decode(stale, endpoint: endpoint) {
                Logger.log(domain: .timeline).warning("回源失败，回退过期缓存: \(key.prefix(56), privacy: .public)")
                return page
            }
            throw error
        }
    }

    /// 端点 key + 游标 → 稳定缓存键（字段名改动只影响新键，旧条目自然被 LRU 淘汰）。
    static func cacheKey(endpoint: APIWebEndpoint, cursor: WebCursor) -> String {
        let query = cursor.queryItems()
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(endpoint.key)?\(query)"
    }

    /// 解码 + 改版归因（错误里只带端点 key，不带 URL/内容，凭证红线）。
    static func decode(_ data: Data, endpoint: APIWebEndpoint) throws -> StatusPage {
        do {
            return try JSONDecoder().decode(TimelinePayload.self, from: data).asPage()
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decode(field: endpoint.key, hint: String(describing: type(of: error)))
        }
    }

    /// 是否允许用过期缓存兜底：瞬时故障（传输/超时/限频/风控/通道不可用/5xx/改版）可以，
    /// 身份与取消类错误（未登录、越权、任务取消、业务错误）不可以。
    static func canServeStale(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return switch api {
        case .transport, .timeout, .rateLimited, .punished, .decode, .channelUnavailable: true
        case .httpStatus(let code): code >= 500 || code == 429
        default: false
        }
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
