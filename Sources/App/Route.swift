import Foundation

/// 集中式导航路由（PLAN D5：`NavigationStack` + Route enum，不用字符串路由表）。
///
/// 约定：每个 tab 内一条独立栈（`[Route]`），栈状态由 `TabView` 持有；
/// 跨 tab 跳转（如从消息跳到某条微博）走 `AppRoute`，由 `RootView` 统一消费。
enum Route: Hashable {
    /// 微博详情（`mid` 为 Web 接口口径的微博 ID）
    case statusDetail(mid: String)
    /// 转发列表（`shownOnlyActiveReply` 对齐 Web 端「查看斗转星移」的取舍）
    case reposts(mid: String)
    /// 评论列表（`maxId` 为游标，见 `Core/APIWeb/Pagination`）
    case comments(mid: String, maxId: String?)
    /// 用户主页
    case userProfile(uid: String)
    /// 话题页
    case topic(name: String)
    /// 大图查看器（`index` 用于 `matchedGeometryEffect` / `glassEffectID` 转场定位）
    case photoViewer(urls: [URL], index: Int)
    /// 搜索关键词结果
    case searchResults(query: String, tab: SearchTab)
    /// 兜底：Web 接口拿不到等价原生结构时的临时网页承载（M0 不放行任何第三方链接）
    case web(URL)
}

/// tab 级跳转意图（跨 tab 需要同时改选中 tab 与目标栈）
enum AppRoute: Hashable {
    case openTab(Tab)
    case to(Route)
}

/// 底部 tab 定义（集中一处，`TabView` 与深链解析共用）
enum Tab: Int, CaseIterable, Identifiable, Sendable {
    case timeline
    case search
    case notifications
    case profile

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .timeline: "首页"
        case .search: "发现"
        case .notifications: "消息"
        case .profile: "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: "house"
        case .search: "magnifyingglass"
        case .notifications: "bell"
        case .profile: "person.crop.circle"
        }
    }
}

/// 搜索三 tab（PLAN M6）
enum SearchTab: String, CaseIterable, Identifiable, Sendable {
    case status = "微博"
    case user = "用户"
    case topic = "话题"

    var id: String {
        rawValue
    }
}
