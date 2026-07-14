import XCTest
@testable import AdblockKeshi

/// ProEntitlementCache（3冗長 + latch で剥奪しない恒久キャッシュ）のテスト。
/// canon: tasks/v4-freemium-dns-plan.md §grandfather（恒久ローカル永続化・剥奪しない）
final class ProEntitlementCacheTests: XCTestCase {

    /// read/write を模す fake レール。forceRead 非 nil で read 失敗/flaky を再現。
    final class FakeFlagStore: ProFlagStore {
        var stored = false
        var forceRead: Bool?
        func readPro() -> Bool { forceRead ?? stored }
        func writePro() { stored = true }
    }

    func test_grant_thenReadsStayTrue_evenIfBackingReadFails() {
        let a = FakeFlagStore(), b = FakeFlagStore(), c = FakeFlagStore()
        let cache = ProEntitlementCache(stores: [a, b, c])
        XCTAssertFalse(cache.isPro())
        cache.grantPro()
        XCTAssertTrue(cache.isPro())
        // 全レールが読めなくなっても（false 返す）memory latch で剥奪しない
        a.forceRead = false; b.forceRead = false; c.forceRead = false
        XCTAssertTrue(cache.isPro(), "一度付与したら flaky read でも剥奪しない")
    }

    func test_anyStoreTrue_isPro() {
        let a = FakeFlagStore(), b = FakeFlagStore(), c = FakeFlagStore()
        b.stored = true   // 例: iCloud KVS で復元された1レールのみ true
        let cache = ProEntitlementCache(stores: [a, b, c])
        XCTAssertTrue(cache.isPro(), "どれか1つでも true なら Pro")
    }

    func test_grant_writesToAllStores() {
        let a = FakeFlagStore(), b = FakeFlagStore(), c = FakeFlagStore()
        let cache = ProEntitlementCache(stores: [a, b, c])
        cache.grantPro()
        XCTAssertTrue(a.stored); XCTAssertTrue(b.stored); XCTAssertTrue(c.stored)
    }

    func test_freshCache_readsPersistedTrue_withoutLatch() {
        // 新規プロセス相当（latch なし）でも永続レールが true なら Pro
        let persisted = FakeFlagStore(); persisted.stored = true
        let cache = ProEntitlementCache(stores: [persisted])
        XCTAssertTrue(cache.isPro())
    }

    func test_allFalse_isNotPro() {
        let cache = ProEntitlementCache(stores: [FakeFlagStore(), FakeFlagStore()])
        XCTAssertFalse(cache.isPro())
    }
}
