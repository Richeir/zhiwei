import SnapshotTesting
import SwiftUI
import XCTest
@testable import ZhiWei

/// 视觉回归（PLAN §8.1「关键 View 的编译期构造 + snapshot-testing 视觉回归（Cell、详情页）」）
///
/// 首次跑要录制基准：`ZHIWEI_SNAPSHOTS=1 Scripts/ci-local.sh test`（会把参考图写进
/// `Tests/UI/__Snapshots__`，**基准图必须入库**，之后 PR 才能比对）。
/// CI 默认开启比对；本地默认跳过，避免新人 clone 后第一眼看到一堆红。
@MainActor
final class StatusCellSnapshotTests: XCTestCase {
    private static let recordingEnabled =
        ProcessInfo.processInfo.environment["ZHIWEI_SNAPSHOTS"] == "1"
            || ProcessInfo.processInfo.environment["CI"] != nil

    private func sampleStatus() -> WBStatus {
        WBStatus(
            id: "5100000000000001",
            bid: "RaBcDe",
            text: "今天试了 <a href=\"#\">#知微#</a>，<a href=\"#\">@richeir</a> 说毛玻璃很省心。",
            createdAt: WebDate(date: Date(timeIntervalSince1970: 1_756_000_000), raw: "Fri Aug 29 12:03:11 +0800 2026"),
            user: WBUser(
                id: "7000000000000001",
                screenName: "伊洛",
                avatarURL: URL(string: "https://wx1.sinaimg.cn/001.jpg"),
                verified: true,
                verifiedType: 0,
                followers: 12400,
                follows: 320,
                statusCount: 4102,
                bio: "写代码，也写微博。"),
            source: "来自 iPhone 客户端",
            pics: (1 ... 3).map { WBPicture(url: URL(string: "https://wx1.sinaimg.cn/bmiddle/00\($0).jpg")!, type: .middle) },
            reposts: 12, comments: 34, attitudes: 1560)
    }

    func testStatusCellCompilesAndRenders() {
        // 编译期构造即有价值：字段改名 / 组件签名变化会在这里第一时间炸
        let view = StatusCell(status: sampleStatus())
        _ = AnyView(view)
    }

    func testStatusCellVisualRegression() throws {
        try XCTSkipUnless(
            Self.recordingEnabled,
            "未开启快照（设 ZHIWEI_SNAPSHOTS=1 首次录制基准图）")
        assertSnapshot(
            of: StatusCell(status: sampleStatus()).frame(width: 375),
            as: .image(layout: .fixed(width: 375, height: 260)),
            named: "statusCell-light")
    }

    func testEmptyAndErrorStatesMatch() throws {
        try XCTSkipUnless(Self.recordingEnabled, "未开启快照")
        assertSnapshot(
            of: SignedOutStateView(login: {}).frame(width: 375),
            as: .image(layout: .fixed(width: 375, height: 220)),
            named: "signedOut")
        assertSnapshot(
            of: ErrorStateView(error: .rateLimited(retryAfterMilliseconds: 1000), retry: {})
                .frame(width: 375),
            as: .image(layout: .fixed(width: 375, height: 220)),
            named: "errorRateLimited")
    }
}
