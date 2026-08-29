import Foundation

// MARK: - 统一错误模型（PLAN §5：`APIError` enum 含 `.punished` case）
//
// 设计要点：
// 1. **风控是一等公民**：`.punished` 不是"失败"的一种，而是需要特定人机协同流程的状态；
//    调用方（Repository / UI）必须显式处理，不能靠 catch-all 吞掉。
// 2. **可枚举、可比对**：`Equatable`，便于单测与快照测试断言；不持有 `Error` 本体
//    （原始错误经 `Logger` 落诊断域，避免把 URL/凭证带进上层）。

enum APIError: Error, Equatable, Sendable {
    /// 网络/系统层失败（可重试）
    case transport(reason: String)
    /// 超时（可重试，计入退避）
    case timeout
    /// 任务被取消（`.task(id:)` 竞态取消、页面销毁），不算错误
    case cancelled
    /// HTTP 非 2xx；432（微博限频）会先经风控识别再决定是否升级为 `.punished`
    case httpStatus(Int)
    /// 未登录 / 会话过期 → 应唤起重新登录（R2）
    case notLoggedIn
    /// 被限频但无验证挑战：退避后重试（R1 的 432 实例）
    case rateLimited(retryAfterMilliseconds: Int?)
    /// 命中风控（滑块/验证码/安全校验页），需要人工验证后重放（R1 缓解措施③）
    case punished(PunishChallenge)
    /// 解码失败：Web 端改版的第一现场（配合契约快照测试，§8.1）
    case decode(field: String?, hint: String)
    /// 业务层返回失败（`ok != 1` 等），保留原始文案便于走查
    case business(code: Int?, message: String?)
    /// 请求被通道拒绝（如目标域不在同源白名单内）
    case forbiddenTarget(URL)
    /// 离屏通道不可用（R7 判据①②失败的兜底表征）
    case channelUnavailable(reason: String)

    /// 是否属于"值得自动重试"的瞬时故障
    ///
    /// `.punished` 与 `.notLoggedIn` 必须走人机协同，**不重试**（重试只会加重风控）。
    var isRetryable: Bool {
        switch self {
        case .transport, .timeout, .rateLimited: true
        case .httpStatus(let code): code >= 500
        default: false
        }
    }

    /// 给用户的说法（不暴露技术细节；文案里不出现"接口/爬虫"字样，与 README 低调姿态一致）
    var userMessage: String {
        switch self {
        case .punished: "微博要求验证你的身份，请完成验证后自动继续"
        case .rateLimited: "请求有点快，稍等一下再试"
        case .notLoggedIn: "登录已过期，请重新登录"
        case .timeout: "网络有点慢，请重试"
        case .cancelled: ""
        case .decode: "内容格式有变化，可能需要在 `Core/APIWeb` 适配"
        case .business(_, let message): message ?? "操作未成功"
        case .transport(let reason): "网络异常（\(reason)）"
        case .httpStatus(let code): "服务返回异常（\(code)）"
        case .forbiddenTarget: "该地址不在允许访问范围内"
        case .channelUnavailable: "数据通道未就绪"
        }
    }
}

/// 风控挑战描述：只带定位信息，不带 cookie/token 内容。
struct PunishChallenge: Sendable, Hashable {
    /// 触发挑战的 URL（唤起可见 WebView 时加载它或其登录页）
    var url: URL
    /// 观测到的 HTTP 状态（微博常见 432 限频）
    var statusCode: Int?
    /// 挑战类型（按回包特征识别；识别不出就归 `.unknown` 走人工）
    var kind: Kind

    enum Kind: String, Sendable, Hashable {
        case slider
        case captcha
        case loginRequired
        /// 兜底：把页面呈现给人，由人判断
        case unknown
    }
}

extension APIError {
    /// 从 HTTP 响应与响应体识别风控/改版信号（R1 缓解措施③的第一环）。
    ///
    /// 判据来自公开案例（432 限频、punish 页、跳登录），字段以实测为准；
    /// 识别逻辑集中在此处，改版时只动一个函数。
    static func classify(statusCode: Int, body: Data?, contentType: String? = nil) -> APIError? {
        if statusCode == 432 {
            return .punished(PunishChallenge(url: Placeholder.punishURL, statusCode: 432, kind: .slider))
        }
        if statusCode == 429 {
            return .rateLimited(retryAfterMilliseconds: nil)
        }
        if statusCode == 401 || statusCode == 403 {
            return .notLoggedIn
        }
        guard (200 ..< 300).contains(statusCode) else { return .httpStatus(statusCode) }

        // 少数情况下状态 200 但内容是验证页/登录页，需按 body 特征识别。
        // 正常 ajax 回包是 JSON（`contentType` 含 json），命中 JSON 就直接放行给解码层，省掉文本嗅探。
        guard contentType?.contains("json") != true else { return nil }
        guard let body, let text = String(data: body, encoding: .utf8)?.lowercased() else { return nil }
        if text.contains("passport.weibo") || text.contains("\"login\""), text.contains("<html") {
            return .notLoggedIn
        }
        if text.contains("punish") || text.contains("slider") || text.contains("验证码") {
            return .punished(PunishChallenge(url: Placeholder.punishURL, statusCode: statusCode, kind: .unknown))
        }
        return nil
    }
}

private enum Placeholder {
    /// 识别阶段拿不到精确 URL 时的占位；真值由调用方补（M1 通道层填入实际触发地址）
    static let punishURL = URL(string: "https://passport.weibo.com/sso/signin")!
}
