import XCTest
@testable import AdblockKeshi

final class RemoteConfigStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let url = URL(string: "https://example.com/flags.json")!

    override func setUp() {
        super.setUp()
        suiteName = "test.RemoteConfig.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore(_ fetcher: RemoteConfigFetching) -> RemoteConfigStore {
        RemoteConfigStore(
            url: url,
            fetcher: fetcher,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private final class StubFetcher: RemoteConfigFetching {
        var responses: [Result<Data, Error>]
        var calls: [URL] = []
        init(_ responses: [Result<Data, Error>]) { self.responses = responses }
        func fetch(url: URL) async throws -> Data {
            calls.append(url)
            return try responses.removeFirst().get()
        }
    }

    private enum StubError: Error { case network }

    func test_fetchAndUpdate_storesValidJSONInCache() async {
        let json = #"{"report_tab_enabled": true, "emergency_kill_switch": false}"#
        let fetcher = StubFetcher([.success(Data(json.utf8))])
        let store = makeStore(fetcher)
        let ok = await store.fetchAndUpdate()
        XCTAssertTrue(ok)
        XCTAssertEqual(fetcher.calls, [url])
        XCTAssertTrue(store.boolValue(forKey: "report_tab_enabled", default: false))
    }

    func test_fetchAndUpdate_networkFailureKeepsExistingCache() async {
        let firstJSON = #"{"report_tab_enabled": false}"#
        let firstStore = makeStore(StubFetcher([.success(Data(firstJSON.utf8))]))
        _ = await firstStore.fetchAndUpdate()
        XCTAssertFalse(firstStore.boolValue(forKey: "report_tab_enabled", default: true))

        let secondStore = makeStore(StubFetcher([.failure(StubError.network)]))
        let ok = await secondStore.fetchAndUpdate()
        XCTAssertFalse(ok)
        XCTAssertFalse(secondStore.boolValue(forKey: "report_tab_enabled", default: true))
    }

    func test_fetchAndUpdate_invalidJSONIsRejectedAndDoesNotPolluteCache() async {
        let invalid = Data("not-json-at-all".utf8)
        let store = makeStore(StubFetcher([.success(invalid)]))
        let ok = await store.fetchAndUpdate()
        XCTAssertFalse(ok)
        XCTAssertTrue(store.boolValue(forKey: "report_tab_enabled", default: true))
        XCTAssertFalse(store.boolValue(forKey: "report_tab_enabled", default: false))
    }

    func test_boolValue_returnsDefaultWhenCacheIsEmpty() {
        let store = makeStore(StubFetcher([]))
        XCTAssertTrue(store.boolValue(forKey: "any_key", default: true))
        XCTAssertFalse(store.boolValue(forKey: "any_key", default: false))
    }

    func test_boolValue_returnsDefaultWhenKeyMissingFromCachedJSON() async {
        let json = #"{"other_flag": true}"#
        let store = makeStore(StubFetcher([.success(Data(json.utf8))]))
        _ = await store.fetchAndUpdate()
        XCTAssertTrue(store.boolValue(forKey: "missing_key", default: true))
        XCTAssertFalse(store.boolValue(forKey: "missing_key", default: false))
    }
}
