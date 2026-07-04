import XCTest
@testable import AdblockKeshi

/// 適用済み variant の記録（applied-rules.json）の永続化テスト。
final class AppliedRulesStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applied-rules-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_read_returns_empty_when_file_missing() {
        let store = AppliedRulesStore(directory: tempDir)
        XCTAssertEqual(store.read(), [:])
    }

    func test_write_then_read_round_trips() throws {
        let store = AppliedRulesStore(directory: tempDir)
        let generatedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let appliedAt = Date(timeIntervalSince1970: 1_780_100_000)
        let records = [
            "merged-rules.json": AppliedRulesRecord(
                sha256: "abc123", generatedAt: generatedAt, ruleCount: 129_000, appliedAt: appliedAt)
        ]
        try store.write(records)

        let loaded = store.read()
        XCTAssertEqual(loaded.count, 1)
        let record = try XCTUnwrap(loaded["merged-rules.json"])
        XCTAssertEqual(record.sha256, "abc123")
        XCTAssertEqual(record.ruleCount, 129_000)
        XCTAssertEqual(
            record.generatedAt.timeIntervalSince1970,
            generatedAt.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(
            record.appliedAt.timeIntervalSince1970,
            appliedAt.timeIntervalSince1970, accuracy: 1.0)
    }

    func test_read_returns_empty_on_corrupt_file() throws {
        let store = AppliedRulesStore(directory: tempDir)
        try Data("{broken json".utf8).write(
            to: tempDir.appendingPathComponent(AppliedRulesStore.filename))
        XCTAssertEqual(store.read(), [:])
    }

    func test_overwrite_updates_existing_variant() throws {
        let store = AppliedRulesStore(directory: tempDir)
        let old = AppliedRulesRecord(
            sha256: "old", generatedAt: Date(), ruleCount: 100, appliedAt: Date())
        let new = AppliedRulesRecord(
            sha256: "new", generatedAt: Date(), ruleCount: 200, appliedAt: Date())
        try store.write(["ad-rules.json": old])
        var records = store.read()
        records["ad-rules.json"] = new
        try store.write(records)
        XCTAssertEqual(store.read()["ad-rules.json"]?.sha256, "new")
    }
}
