import Foundation

// MARK: - `openapi/` 留位（PLAN D9：「`APIWeb` 保留后端抽象（`web/` 默认实现，`openapi/` 留位）」）
//
// 这里**故意只有一个协议**，不是实现。它存在的意义是把话说清楚：
// 路线 B（Web 通道）长期失效时，换后端只需要提供另一个 `TimelineProviding` 实现，
// Feature 层与 UI 零改动——这也是 §1.1 说"不上开放平台申请"却仍要留这条缝的理由。
//
// 真要走开放平台：需要企业/个人资质申请、字段口径完全不同（`statuses/friends_timeline`），
// 且限流规则按 access_token 计，属于另一个项目量级的决策，届时先在 PLAN 记一条 D10。

/// 与 `WebTimelineProvider` 同形的开放平台实现占位
@MainActor
struct OpenAPITimelineProvider: TimelineProviding {
    /// 不持有 WebViewChannel：开放平台走独立 OAuth，与路线 B 完全正交
    func loadPage(after _: WebCursor) async throws -> StatusPage {
        throw APIError.business(code: nil, message: "开放平台后端未实现（留位）")
    }
}
