import XCTest
@testable import ZhiWei

/// DTO 解码单测（PLAN §8.1「单元测试：`APIWeb` DTO 解码」，目标覆盖 ≥70%）
///
/// 这些断言就是"Web 改版时先响的警报"：字段口径一变，测试红在解码层而不是线上白屏。
final class DTODecodingTests: XCTestCase {
    func testHomeTimelineDecodesBothShapes() throws {
        let payload = try Fixtures.decoded(TimelinePayload.self, named: "timeline.home")
        XCTAssertEqual(payload.statuses.count, 3, "list 里三条都应解出")
        XCTAssertEqual(payload.nextMaxID, "1725000000000", "max_id 原样带出，供游标推进")
        XCTAssertTrue(payload.hasMore)
    }

    @MainActor
    func testFirstStatusNormalizesFields() throws {
        let page = try Fixtures.decoded(TimelinePayload.self, named: "timeline.home")
        let status = try XCTUnwrap(page.statuses.first)

        XCTAssertEqual(status.id, "5100000000000001", "mid 优先于 id")
        XCTAssertEqual(status.bid, "RaBcDe")
        XCTAssertEqual(status.user?.screenName, "伊洛")
        XCTAssertEqual(status.user?.followers, 124_000, "\"12.4万\" 必须被 LooseInt 消化")
        XCTAssertEqual(status.user?.verifiedType, 0)
        XCTAssertTrue(status.user?.verified == true)
        XCTAssertEqual(status.reposts, 12, "字符串数字 \"12\" 要能解")
        XCTAssertEqual(status.attitudes, 15600)
        XCTAssertEqual(status.pics.count, 2)
        XCTAssertEqual(status.pics.first?.url.absoluteString, "https://wx1.sinaimg.cn/bmiddle/001.jpg")
        XCTAssertNotNil(status.createdAt?.date, "EEE MMM dd HH:mm:ss Z yyyy 口径")
        XCTAssertFalse(status.isLongText)
    }

    func testRetweetAndPicInfos() throws {
        let page = try Fixtures.decoded(TimelinePayload.self, named: "timeline.home")
        let repost = try XCTUnwrap(page.statuses.dropFirst().first)
        let original = try XCTUnwrap(repost.retweeted)
        XCTAssertEqual(original.user?.screenName, "某个博主")
        XCTAssertEqual(original.pics.count, 1, "pic_infos 字典口径要能拍平成数组")
        XCTAssertEqual(
            original.pics.first?.url.absoluteString,
            "https://wx3.sinaimg.cn/large/003.jpg",
            "查看器优先取 largest")
    }

    func testEpochSecondsDateAndVideo() throws {
        let page = try Fixtures.decoded(TimelinePayload.self, named: "timeline.home")
        let videoStatus = try XCTUnwrap(page.statuses.last)
        XCTAssertNotNil(videoStatus.createdAt?.date, "epoch 秒也要能解")
        let video = try XCTUnwrap(videoStatus.video)
        XCTAssertEqual(video.streamURL?.absoluteString, "https://f.video.weibocdn.com/004.mp4")
        XCTAssertEqual(video.title, "一段演示")
    }

    func testMissingFieldsNeverFailDecoding() {
        // 只给 id 的极简回包：其余字段全部缺省也不许整条失败（R1：字段消失是常态）
        let json = #"{"mid":"1","user":{"screen_name":"某人"}}"#
        let status = try? JSONDecoder().decode(WBStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status?.id, "1")
        XCTAssertEqual(status?.user?.screenName, "某人")
        XCTAssertEqual(status?.reposts, 0)
        XCTAssertTrue(status?.pics.isEmpty == true)
    }

    func testWebDateParsesKnownFormats() {
        XCTAssertNotNil(WebDate.parse("Tue Aug 29 12:00:00 +0800 2026"))
        XCTAssertNotNil(WebDate.parse("2026-08-29 12:00:00"))
        XCTAssertNotNil(WebDate.parse("2026-08-29"))
        XCTAssertNotNil(WebDate.parse("1756468990"))
        XCTAssertNil(WebDate.parse("不是时间"))
    }

    func testEnvelopeRejectsFailedBusinessResponse() {
        let json = #"{"ok":0,"msg":"unauthorized"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(WebEnvelope<WBStatus>.self, from: Data(json.utf8))) { error in
            guard case APIError.business(let code, let message)? = error as? APIError else {
                return XCTFail("应解成 APIError.business，实际 \(String(describing: error))")
            }
            XCTAssertEqual(code, 0)
            XCTAssertEqual(message, "unauthorized")
        }
    }
}
