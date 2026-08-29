import Foundation

// MARK: - 读接口薄层（PLAN D6「Repository 层」的最小形态）
//
// 一个泛型入口把「端点 → 车道① → 信封解码」串起来。
// 写操作（发布/点赞/关注）走 `WebWriter`（M3/M4），因为它需要 XSRF 与乐观更新，语义不同。

@MainActor
struct WebReader {
    let channel: any WebViewChannel

    /// 读一个端点。`EnvelopeStyle` 决定回包是 `data` 直取还是容器嵌套。
    func load<Payload: Decodable>(
        _ endpoint: APIWebEndpoint,
        query: [String: String] = [:],
        as _: Payload.Type = Payload.self) async throws -> Payload {
        let request = WebChannelRequest(
            url: endpoint.url,
            method: endpoint.method,
            query: query,
            headers: endpoint.requestHeaders())
        let data = try await channel.fetch(request)
        do {
            // 先按"直接就是 Payload"试，再按 `{"ok":1,"data":…}` 试——两种口径都存在
            if let direct = try? JSONDecoder().decode(Payload.self, from: data) {
                return direct
            }
            let envelope = try JSONDecoder().decode(WebEnvelope<Payload>.self, from: data)
            guard let payload = envelope.data else {
                throw APIError.decode(field: endpoint.key, hint: "信封里没有 data")
            }
            return payload
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decode(field: endpoint.key, hint: String(describing: Swift.type(of: error)))
        }
    }
}
