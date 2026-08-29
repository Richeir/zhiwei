import Foundation

// MARK: - 端点注册表（PLAN §2.2 / R1 缓解措施④：「端点全部收敛在 `Core/APIWeb/`，改版只动这里」）
//
// 三条纪律：
//   1. 业务代码**不得**手拼 URL；要发请求就先在这里注册。
//   2. `method` / `referer` / `needsXSRF` 是 Web 端校验的一部分（R7 判据④），逐条标注。
//   3. 每个端点带一个 `key`（注册表主键）：日志与契约快照测试用它定位，URL 换了不用改测试文件名。
//
// ⚠️ 下表的 URL 口径来自公开资料与 Web 端习惯，**M2 起逐个实测校正**；
//    实测前不要把任何端点当作既定事实（PLAN §5 边界）。

struct APIWebEndpoint: Sendable, Hashable {
    enum Purpose: String, Sendable {
        case read // 只读：走车道①（页面内 fetch）
        case write // 写操作：走车道②（原生 URLSession，上传/发布）
        case probe // 会话探测：车道② 轻量直发
    }

    /// 注册表主键（同时是快照文件名）
    var key: String
    var url: URL
    var method: WebChannelRequest.Method
    var purpose: Purpose
    /// 服务端会校验 Referer/Origin（R7 判据④）
    var referer: URL?
    /// 写操作需要 `XSRF-TOKEN` 头（值来自 WebKit cookie，绝不落盘）
    var needsXSRF: Bool
    /// 人类可读备注：实测结论往这里写，成为唯一的端点事实来源
    var note: String

    init(
        key: String,
        _ urlString: String,
        method: WebChannelRequest.Method = .get,
        purpose: Purpose = .read,
        referer: String? = nil,
        needsXSRF: Bool = false,
        note: String = "") {
        self.key = key
        self.url = URL(string: urlString)!
        self.method = method
        self.purpose = purpose
        self.referer = referer.flatMap { URL(string: $0) }
        self.needsXSRF = needsXSRF
        self.note = note
    }
}

// MARK: 注册表

extension APIWebEndpoint {
    /// —— 会话 ——
    static let sessionProbe = APIWebEndpoint(
        key: "session.probe",
        "https://weibo.com/ajax/profile/overview",
        purpose: .probe, referer: "https://weibo.com/",
        note: "登录态探测：200 且带 data 即视为已登录；口径待实测（备选 m.weibo.cn/api/config）")
    static let logout = APIWebEndpoint(
        key: "session.logout",
        "https://passport.weibo.com/bodysignout/signup",
        method: .post, purpose: .write, referer: "https://weibo.com/",
        note: "登出走 Web 端；App 侧同时清 WKWebsiteDataStore（M1）")

    /// —— 时间线 ——
    static let homeTimeline = APIWebEndpoint(
        key: "timeline.home",
        "https://weibo.com/ajax/statuses/friends_timeline",
        referer: "https://weibo.com/",
        note: "关注时间线主口径；游标 max_id / 分页 page 均需实测确认")
    static let homeTimelineFallback = APIWebEndpoint(
        key: "timeline.home.fallback",
        "https://m.weibo.cn/api/container/getIndex",
        referer: "https://m.weibo.cn/",
        note: "m 站兜底：containerid 口径（102803 系）；实测后再定 containerid 取值")

    /// —— 详情与互动 ——
    static let statusShow = APIWebEndpoint(
        key: "status.show", "https://weibo.com/ajax/statuses/show",
        referer: "https://weibo.com/", note: "详情：id 参数；长文补齐字段实测")
    static let longTextFetch = APIWebEndpoint(
        key: "status.longtext", "https://weibo.com/ajax/statuses/longtext",
        referer: "https://weibo.com/", note: "isLongText 时补正文")
    static let commentsList = APIWebEndpoint(
        key: "comments.list", "https://weibo.com/ajax/comment/show",
        referer: "https://weibo.com/", note: "评论列表（含楼中楼）")
    static let commentCreate = APIWebEndpoint(
        key: "comments.create", "https://weibo.com/ajax/comment/add",
        method: .post, purpose: .write, referer: "https://weibo.com/", needsXSRF: true, note: "发评论")
    static let repostList = APIWebEndpoint(
        key: "reposts.list", "https://weibo.com/ajax/statuses/repostTimeline",
        referer: "https://weibo.com/", note: "转发列表")
    static let repostCreate = APIWebEndpoint(
        key: "reposts.create", "https://weibo.com/ajax/statuses/repost",
        method: .post, purpose: .write, referer: "https://weibo.com/", needsXSRF: true, note: "带意见转发")
    static let likeCreate = APIWebEndpoint(
        key: "likes.create", "https://weibo.com/ajax/statuses/attitudes_create",
        method: .post, purpose: .write, referer: "https://weibo.com/", needsXSRF: true, note: "点赞")
    static let likeDestroy = APIWebEndpoint(
        key: "likes.destroy", "https://weibo.com/ajax/statuses/attitudes_destroy",
        method: .post, purpose: .write, referer: "https://weibo.com/", needsXSRF: true, note: "取消点赞")

    /// —— 发布 ——
    static let publishText = APIWebEndpoint(
        key: "compose.publish", "https://weibo.com/ajax/statuses/update",
        method: .post, purpose: .write, referer: "https://weibo.com/compose/", needsXSRF: true,
        note: "发纯文本；status 参数 + visible 范围")
    static let uploadPicture = APIWebEndpoint(
        key: "compose.upload", "https://weibo.com/ajax/statuses/uploadPic",
        method: .post, purpose: .write, referer: "https://weibo.com/compose/", needsXSRF: true,
        note: "multipart 上传（R7 判据④ 的实测对象：Referer/Origin/参数校验）")

    /// —— 用户 ——
    static let profileOverview = APIWebEndpoint(
        key: "profile.overview", "https://weibo.com/ajax/profile/info",
        referer: "https://weibo.com/", note: "资料卡；containerid 取微博列表")
    static let userStatuses = APIWebEndpoint(
        key: "profile.statuses", "https://weibo.com/ajax/profile/container",
        referer: "https://weibo.com/", note: "某人的微博列表（container 型，feature/containerid 参数实测）")
    static let followCreate = APIWebEndpoint(
        key: "profile.follow", "https://weibo.com/ajax/friendships/follow",
        method: .post, purpose: .write, referer: "https://weibo.com/", needsXSRF: true, note: "关注")
    static let followDestroy = APIWebEndpoint(
        key: "profile.unfollow", "https://weibo.com/ajax/friendships/destroy",
        method: .post, purpose: .write, referer: "https://weibo.com/", needsXSRF: true, note: "取关")

    /// —— 搜索与消息 ——
    static let searchStatus = APIWebEndpoint(
        key: "search.status", "https://weibo.com/ajax/side/search",
        referer: "https://s.weibo.com/", note: "M6：三 tab 之一")
    static let hotSearch = APIWebEndpoint(
        key: "search.hot", "https://weibo.com/ajax/side/hotSearch",
        referer: "https://weibo.com/", note: "M6：侧边热搜榜")
    static let notificationAt = APIWebEndpoint(
        key: "notify.at", "https://weibo.com/ajax/notice/unread",
        referer: "https://weibo.com/", note: "M7：@我 / 评论 / 转发 与未读数")

    /// 全部已注册端点（注册表的唯一遍历入口；CI 可用它做覆盖率体检）
    static let registry: [String: APIWebEndpoint] = {
        let all: [APIWebEndpoint] = [
            .sessionProbe, .logout,
            .homeTimeline, .homeTimelineFallback,
            .statusShow, .longTextFetch,
            .commentsList, .commentCreate,
            .repostList, .repostCreate,
            .likeCreate, .likeDestroy,
            .publishText, .uploadPicture,
            .profileOverview, .userStatuses, .followCreate, .followDestroy,
            .searchStatus, .hotSearch, .notificationAt
        ]
        // 主键撞车时保留后者并就地断言可发现（避免运行时 trap）
        return Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    static func registered(key: String) -> APIWebEndpoint? {
        registry[key]
    }

    /// 组装请求头。Referer/Origin 是服务端校验项（R7 判据④），缺一个就可能被踢回验证页。
    ///
    /// `xsrfToken` 只在写操作时用，**来自 WebKit cookie，禁止落盘与写日志**（凭证红线）。
    func requestHeaders(xsrfToken: String? = nil) -> [String: String] {
        var headers: [String: String] = [:]
        if let referer {
            headers["Referer"] = referer.absoluteString
            headers["Origin"] = referer.origin
        }
        if needsXSRF, let xsrfToken, !xsrfToken.isEmpty {
            headers["X-XSRF-TOKEN"] = xsrfToken
        }
        return headers
    }
}

extension URL {
    /// `scheme://host[:port]`——Origin 头的口径
    var origin: String {
        guard let scheme, let host else { return absoluteString }
        let portPart = port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(portPart)"
    }
}
