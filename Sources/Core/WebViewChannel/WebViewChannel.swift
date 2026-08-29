import Foundation

// MARK: - 通道协议定样（PLAN §5：`WebViewChannel { func fetch(_:) async throws -> Data }`）
//
// 这是全 App 的**唯一网络入口**（§7「所有网络入口收敛到 WebViewChannel 协议，任何库不得绕行限流器」）。
// 标 `@MainActor`：车道① 要驱动 WKWebView 的 `evaluateJavaScript`（系统要求主线程），
// 而车道② 的 Cookie 同步源 `WKHTTPCookieStore` 同样绑定 WebKit 的调度环境；
// 把隔离边界定在 MainActor，避免在通道层再叠一层 actor 跳板（M1 若要下沉再拆）。

@MainActor
protocol WebViewChannel: AnyObject {
    /// 当前通道状态（离屏 WebView 是否存活、会话是否可用）
    var state: ChannelState { get }

    /// 车道①：在已登录的 weibo.com 同源页面内执行 fetch，结构化回传（D9）
    func fetch(_ request: WebChannelRequest) async throws -> Data

    /// 车道②：原生 URLSession + 从 `WKHTTPCookieStore` 同步来的 Cookie（含 httpOnly）。
    /// 主要用于上传/发布——URLSession 不受 CORS 约束（D9 质变点 b）
    func sendNative(_ request: NativeRequest) async throws -> Data

    /// 轻量会话探测（车道②直发，不依赖页面上下文）——M1 的「会话检测」入口
    func probeSession() async throws -> SessionProbe

    /// 风控降级链路第 2 步：唤起**可见** WKWebView 让用户人工过滑块/验证码（R1 缓解措施③）
    func presentVerification(_ challenge: PunishChallenge) async throws
}

// MARK: - 请求模型

/// 车道① 请求：一次同源 XHR/fetch。
///
/// 注意：`query`/`body` 由调用方（`Core/APIWeb`）按 Web 端实测口径组装，
/// 通道层不做业务字段翻译——通道不知道"微博"是什么，这样改版时只需动 `APIWeb`。
struct WebChannelRequest: Sendable, Hashable {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    /// 完整 URL（scheme+host 必须是 weibo.com 系，见 `allowedHosts`）
    var url: URL
    var method: Method = .get
    var query: [String: String] = [:]
    /// 表单字段（`application/x-www-form-urlencoded`，Web 端 ajax 的主流口径）
    var form: [String: String] = [:]
    /// 额外请求头（Referer/Origin 按服务端校验需要补齐）
    var headers: [String: String] = [:]
    /// 关联 ID：回包按此配对（并发 ≤2 时必需）
    var id: UUID = UUID()

    /// 同源域白名单：不在名单内的 URL 一律拒绝，避免通道被当成任意 URL 的代理（R1 低调 + 越权风险）
    static let allowedHosts: Set<String> = [
        "weibo.com", "www.weibo.com", "m.weibo.cn", "weibo.cn",
        "passport.weibo.com", "passport.weibo.cn", "s.weibo.com"
    ]

    var isAllowedHost: Bool {
        guard let host = url.host else { return false }
        return Self.allowedHosts.contains(host)
            || Self.allowedHosts.contains(where: { host.hasSuffix(".\($0)") })
    }
}

/// 车道② 请求：原生 URLSession 直发。上传/发布专用。
struct NativeRequest: Sendable, Hashable {
    enum Body: Sendable, Hashable {
        case none
        case form([String: String])
        /// multipart：field 名 → 值 / 文件段
        case multipart([MultipartPart])
    }

    struct MultipartPart: Sendable, Hashable {
        enum Value: Sendable, Hashable {
            case text(String)
            case file(name: String, mimeType: String, data: Data)
        }

        var field: String
        var value: Value
    }

    var url: URL
    var method: String = "POST"
    var headers: [String: String] = [:]
    var body: Body = .none
}

// MARK: - 状态与探测结果

/// 通道状态机（M0 只定样；状态迁移在 M1 的 `WebViewChannelLive` 里做实）
enum ChannelState: String, Sendable, Hashable {
    /// 离屏 WebView 尚未创建
    case idle
    /// 已创建、页面已就绪（可发同源请求）
    case ready
    /// 页面被系统挂起 / JS 上下文丢失（R7 判据①失败的表征）
    case suspended
    /// 命中风控，等待人工验证（R1 缓解措施③）
    case punished
    /// 未登录或会话过期（R2）
    case signedOut
}

/// 会话探测结果（不携带任何凭证内容）
struct SessionProbe: Sendable, Hashable {
    var isLoggedIn: Bool
    /// 探测到的用户标识（`uid` 来自接口回包，不是 cookie 解析）
    var uid: String?
    /// 是否观察到登录所需的 httpOnly Cookie 存在（R7 判据③，只记"存在"，不记值）
    var sawLoginCookies: Bool
    /// 探测耗时，用于诊断
    var elapsedMilliseconds: Int
}
