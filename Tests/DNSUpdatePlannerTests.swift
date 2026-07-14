import XCTest
@testable import AdblockKeshi

/// DNSUpdatePlanner（self-fetch 更新要否の純関数）のテスト。
final class DNSUpdatePlannerTests: XCTestCase {

    private let manifestJSON = """
    {"dns-rules_sha256":"abc123","dns-rules_bytes":749,"dns-rules_count":41,"generated_at":"2026-07-15T00:00:00Z"}
    """

    func test_parseManifest_extractsShaAndBytes() throws {
        let m = try XCTUnwrap(DNSUpdatePlanner.parseManifest(Data(manifestJSON.utf8)))
        XCTAssertEqual(m.sha256, "abc123")
        XCTAssertEqual(m.bytes, 749)
    }

    func test_parseManifest_returnsNil_forGarbage() {
        XCTAssertNil(DNSUpdatePlanner.parseManifest(Data("not json".utf8)))
    }

    func test_needsUpdate_true_whenLocalMissing() {
        let m = DNSUpdatePlanner.Manifest(sha256: "abc123", bytes: 749)
        XCTAssertTrue(DNSUpdatePlanner.needsUpdate(localSHA: nil, remote: m))
    }

    func test_needsUpdate_true_whenShaDiffers() {
        let m = DNSUpdatePlanner.Manifest(sha256: "abc123", bytes: 749)
        XCTAssertTrue(DNSUpdatePlanner.needsUpdate(localSHA: "old999", remote: m))
    }

    func test_needsUpdate_false_whenShaMatches() {
        let m = DNSUpdatePlanner.Manifest(sha256: "abc123", bytes: 749)
        XCTAssertFalse(DNSUpdatePlanner.needsUpdate(localSHA: "abc123", remote: m))
    }
}
