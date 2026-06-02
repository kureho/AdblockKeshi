import XCTest
@testable import AdblockKeshi

final class StateStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: StateStore!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = StateStore(stateFileURL: tempDir.appendingPathComponent("state.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_read_when_file_missing_returns_defaults_both_enabled() {
        let state = store.read()
        XCTAssertTrue(state.adEnabled)
        XCTAssertTrue(state.securityEnabled)
    }

    func test_write_and_read_roundtrip() throws {
        let s1 = BlockerTogglesState(adEnabled: false, securityEnabled: true, updatedAt: Date())
        try store.write(s1)
        let s2 = store.read()
        XCTAssertEqual(s1.adEnabled, s2.adEnabled)
        XCTAssertEqual(s1.securityEnabled, s2.securityEnabled)
    }

    func test_read_when_corrupt_returns_defaults() throws {
        try "not-json-{".data(using: .utf8)!
            .write(to: tempDir.appendingPathComponent("state.json"))
        let state = store.read()
        XCTAssertTrue(state.adEnabled)
        XCTAssertTrue(state.securityEnabled)
    }

    func test_write_creates_non_empty_file() throws {
        let s1 = BlockerTogglesState(adEnabled: true, securityEnabled: false)
        try store.write(s1)
        let data = try Data(contentsOf: tempDir.appendingPathComponent("state.json"))
        XCTAssertFalse(data.isEmpty)
    }

    func test_all_four_combinations_persist_correctly() throws {
        let cases: [(Bool, Bool)] = [(true, true), (true, false), (false, true), (false, false)]
        for (ad, sec) in cases {
            let s = BlockerTogglesState(adEnabled: ad, securityEnabled: sec)
            try store.write(s)
            let read = store.read()
            XCTAssertEqual(read.adEnabled, ad, "ad=\(ad) sec=\(sec)")
            XCTAssertEqual(read.securityEnabled, sec, "ad=\(ad) sec=\(sec)")
        }
    }

    // MARK: - BlockerListResolver state-aware filename mapping

    func test_resolver_filename_for_all_four_states() {
        let resolver = BlockerListResolver()
        XCTAssertEqual(resolver.filename(for: BlockerTogglesState(adEnabled: true, securityEnabled: true)), "merged-rules.json")
        XCTAssertEqual(resolver.filename(for: BlockerTogglesState(adEnabled: true, securityEnabled: false)), "ad-rules.json")
        XCTAssertEqual(resolver.filename(for: BlockerTogglesState(adEnabled: false, securityEnabled: true)), "security-rules.json")
        XCTAssertEqual(resolver.filename(for: BlockerTogglesState(adEnabled: false, securityEnabled: false)), "empty-rules.json")
    }
}
