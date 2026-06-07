import XCTest
@testable import AdblockKeshi

final class FeatureFlagsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.FeatureFlags.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private struct UnusedFetcher: RemoteConfigFetching {
        func fetch(url: URL) async throws -> Data { fatalError("unused in this test") }
    }

    private func storeSeeded(with dict: [String: Any]) -> RemoteConfigStore {
        let data = try! JSONSerialization.data(withJSONObject: dict)
        defaults.set(data, forKey: RemoteConfigStore.cachedJSONUserDefaultsKey)
        return RemoteConfigStore(
            url: URL(string: "https://example.com")!,
            fetcher: UnusedFetcher(),
            defaults: defaults,
            now: { Date() }
        )
    }

    private func emptyStore() -> RemoteConfigStore {
        RemoteConfigStore(
            url: URL(string: "https://example.com")!,
            fetcher: UnusedFetcher(),
            defaults: defaults,
            now: { Date() }
        )
    }

    // Spec rev4 §6 evaluation order: `emergency_kill_switch` is fail-CLOSED on
    // the first network failure, so a no-cache cold start must hide Tab B
    // until the CDN confirms `false`.
    func test_reportTabEnabled_isFalseWhenNoCache_failClosed() {
        XCTAssertFalse(FeatureFlags.reportTabEnabled(store: emptyStore()))
    }

    func test_reportTabEnabled_isTrueAfterCDNConfirmsKillSwitchFalse() {
        let store = storeSeeded(with: [
            "report_tab_enabled": true,
            "emergency_kill_switch": false,
        ])
        XCTAssertTrue(FeatureFlags.reportTabEnabled(store: store))
    }

    func test_reportTabEnabled_isFalseWhenKillSwitchOn_evenIfReportTabFlagOn() {
        let store = storeSeeded(with: [
            "report_tab_enabled": true,
            "emergency_kill_switch": true,
        ])
        XCTAssertFalse(FeatureFlags.reportTabEnabled(store: store))
    }

    func test_reportTabEnabled_isFalseWhenReportTabFlagOff_andKillSwitchOff() {
        let store = storeSeeded(with: [
            "report_tab_enabled": false,
            "emergency_kill_switch": false,
        ])
        XCTAssertFalse(FeatureFlags.reportTabEnabled(store: store))
    }

    func test_emergencyKillSwitchEnabled_defaultsToTrueWhenNoCache_failClosed() {
        XCTAssertTrue(FeatureFlags.emergencyKillSwitchEnabled(store: emptyStore()))
    }

    func test_emergencyKillSwitchEnabled_reflectsCachedFlag() {
        let onStore = storeSeeded(with: ["emergency_kill_switch": true])
        XCTAssertTrue(FeatureFlags.emergencyKillSwitchEnabled(store: onStore))
        let offStore = storeSeeded(with: ["emergency_kill_switch": false])
        XCTAssertFalse(FeatureFlags.emergencyKillSwitchEnabled(store: offStore))
    }
}
