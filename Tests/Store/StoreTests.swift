import XCTest
@testable import ZhiWei

/// Store 层单测（PLAN §8.1「Store 层」）+ §5 凭证红线的可执行化检查
final class StoreTests: XCTestCase {
    // MARK: 草稿

    func testDraftSaveDedupesSameText() {
        let store = DraftStore(store: InMemoryKVStore())
        store.save(Draft(text: "同一段话", now: .init(timeIntervalSince1970: 100)))
        store.save(Draft(text: "同一段话", now: .init(timeIntervalSince1970: 200)))
        XCTAssertEqual(store.all().count, 1, "自动保存不该堆出重复草稿")
        XCTAssertEqual(store.all().first?.updatedAt.timeIntervalSince1970 ?? 0, 200, accuracy: 1)
    }

    func testDraftCapacityIsBounded() {
        let store = DraftStore(store: InMemoryKVStore())
        for index in 0 ..< 25 {
            store.save(Draft(text: "草稿 \(index)", now: .init(timeIntervalSince1970: Double(index))))
        }
        XCTAssertEqual(store.all().count, DraftStore.capacity)
        XCTAssertEqual(store.all().first?.text, "草稿 24", "新的在前")
    }

    func testDraftDeleteAndClear() {
        let kv = InMemoryKVStore()
        let store = DraftStore(store: kv)
        let draft = Draft(text: "要删的")
        store.save(draft)
        XCTAssertTrue(store.delete(draft))
        XCTAssertTrue(store.all().isEmpty)
    }

    // MARK: 搜索历史

    func testSearchHistoryIsLRUAndDeduped() {
        let store = SearchHistoryStore(store: InMemoryKVStore())
        store.record("swift", tab: .status, at: .init(timeIntervalSince1970: 1))
        store.record("swiftui", tab: .user, at: .init(timeIntervalSince1970: 2))
        store.record("swift", tab: .status, at: .init(timeIntervalSince1970: 3))

        let recent = store.recent(limit: 10)
        XCTAssertEqual(recent.map(\.query), ["swift", "swiftui"], "重复词要提到最前而不是新增")
        XCTAssertEqual(recent.first?.at.timeIntervalSince1970 ?? 0, 3, accuracy: 1)
    }

    func testBlankSearchIsNotRecorded() {
        let store = SearchHistoryStore(store: InMemoryKVStore())
        store.record("   ", tab: .status)
        XCTAssertTrue(store.recent().isEmpty)
    }

    func testHistoryRespectsCapacity() {
        let store = SearchHistoryStore(store: InMemoryKVStore())
        for index in 0 ..< 40 {
            store.record("关键词\(index)", tab: .status)
        }
        XCTAssertEqual(store.recent(limit: 100).count, SearchHistoryStore.capacity)
    }

    // MARK: 偏好

    func testStalePreferenceDefaults() {
        let kv = InMemoryKVStore()
        XCTAssertEqual(Preferences.timelineStale(kv), Preferences.defaultStaleMilliseconds)
        Preferences.setTimelineStale(600_000, store: kv)
        XCTAssertEqual(Preferences.timelineStale(kv), 600_000)
        Preferences.setTimelineStale(-5, store: kv)
        XCTAssertEqual(Preferences.timelineStale(kv), 0, "不许出现负数缓存时长")
    }

    // MARK: 凭证红线（§5：登录凭证不落 App 存储）

    func testCredentialShapedKeysAreRefused() {
        let kv = KVDefaults(suiteName: "dev.zhiwei.tests.\(UUID().uuidString)")
        for name in ["cookie.SUB", "auth_token", "XSRF-TOKEN", "user.password", "sso_ticket"] {
            XCTAssertFalse(
                kv.setCodable("anything", for: StoreKey(name)),
                "键名 \(name) 看起来像凭证，必须拒写（PLAN §5 红线）")
            XCTAssertNil(kv.string(StoreKey(name)))
        }
    }

    func testGuardIsCheckedOnEveryWritePath() {
        let kv = KVDefaults(suiteName: "dev.zhiwei.tests.\(UUID().uuidString)")
        kv.setString("v", for: StoreKey("cookie.like"))
        XCTAssertNil(kv.string(StoreKey("cookie.like")), "setString 也必须过闸，否则红线形同虚设")
        kv.setInt(1, for: StoreKey("auth.count"))
        XCTAssertNil(kv.int(StoreKey("auth.count")))
    }

    func testNormalKeysStillWork() {
        let kv = KVDefaults(suiteName: "dev.zhiwei.tests.\(UUID().uuidString)")
        XCTAssertTrue(kv.setCodable([1, 2, 3], for: .lastSeenTimelineCursor))
        XCTAssertEqual(kv.codable([Int].self, for: .lastSeenTimelineCursor), [1, 2, 3])
    }
}
