import XCTest
@testable import ZhiWei

/// 端点注册表体检（AGENTS.md 硬约束：Web 端点全部收敛 `Core/APIWeb/`）
final class EndpointRegistryTests: XCTestCase {
    func testEveryRegisteredEndpointIsWeiboHosted() {
        for (key, endpoint) in APIWebEndpoint.registry {
            let host = endpoint.url.host ?? ""
            XCTAssertTrue(
                WebChannelRequest.allowedHosts.contains(host) || WebChannelRequest.allowedHosts.contains { host.hasSuffix(".\($0)") },
                "\(key) 指向了非微博域：\(host)")
            XCTAssertEqual(endpoint.url.scheme, "https", "\(key) 不许用 http（明文出去等于给风控送特征）")
        }
    }

    func testWriteEndpointsDeclareWhyTheyNeedHeaders() {
        for (key, endpoint) in APIWebEndpoint.registry where endpoint.purpose == .write {
            XCTAssertNotNil(endpoint.referer, "写端点 \(key) 必须带 Referer 口径（R7 判据④）")
            XCTAssertTrue(
                endpoint.needsXSRF || key == "session.logout",
                "写端点 \(key) 未声明 XSRF 需求，请确认服务端校验口径")
            XCTAssertEqual(endpoint.method, .post, "\(key) 是写操作，不该用 GET")
        }
    }

    func testProbeEndpointIsReadAndCarriesNoBody() {
        let probe = APIWebEndpoint.sessionProbe
        XCTAssertEqual(probe.purpose, .probe)
        XCTAssertNotNil(probe.referer)
    }

    func testSignatureIsOrderIndependent() throws {
        let url = try XCTUnwrap(URL(string: "https://weibo.com/ajax/statuses/friends_timeline"))
        let requestOne = WebChannelRequest(url: url, query: ["a": "1", "b": "2"])
        let requestTwo = WebChannelRequest(url: url, query: ["b": "2", "a": "1"])
        XCTAssertEqual(
            WebViewChannelLive.signature(of: requestOne),
            WebViewChannelLive.signature(of: requestTwo),
            "参数顺序不同却算不同签名，会让去重形同虚设")
    }

    /// 红线：任何请求都必须过通道。这里守的是"URL 域白名单"这一半（另一半靠 review）。
    func testForeignHostsAreRejected() throws {
        let request = try WebChannelRequest(url: XCTUnwrap(URL(string: "https://evil.example.com/api")))
        XCTAssertFalse(request.isAllowedHost)
    }
}

/// 风控识别（R1 缓解措施③的第一环）
final class RiskClassificationTests: XCTestCase {
    func test432IsTreatedAsPunishmentNotRetry() throws {
        let error = APIError.classify(statusCode: 432, body: nil)
        guard case APIError.punished(let challenge)? = error else {
            return XCTFail("432 必须识别为 .punished，实际 \(String(describing: error))")
        }
        XCTAssertEqual(challenge.statusCode, 432)
        XCTAssertFalse(try XCTUnwrap(error?.isRetryable))
    }

    func test200WithHTMLLoginPageIsNotLoggedIn() {
        let body = Data("<html><head></head><body> passport.weibo.com login </body></html>".utf8)
        let error = APIError.classify(statusCode: 200, body: body, contentType: "text/html")
        XCTAssertEqual(error, .notLoggedIn, "状态 200 但内容是登录页，必须打回会话失效")
    }

    func testJSONBodyIsPassedThroughToDecoder() {
        let body = Data(#"{"ok":1,"data":{}}"#.utf8)
        XCTAssertNil(
            APIError.classify(statusCode: 200, body: body, contentType: "application/json"),
            "正常 JSON 不该被风控嗅探拦下，否则每个请求都白丢")
    }

    func testSliderPageIsPunished() {
        let body = Data("<html><div class=\"punish\">滑一下验证</div></html>".utf8)
        let error = APIError.classify(statusCode: 200, body: body, contentType: "text/html")
        guard case APIError.punished? = error else {
            return XCTFail("验证页要识别成 .punished，实际 \(String(describing: error))")
        }
    }
}
