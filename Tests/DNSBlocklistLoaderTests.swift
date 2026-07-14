import XCTest
@testable import AdblockKeshi

/// DNSBlocklistLoader（curated ∪ self の実効ブロックリスト構築）のテスト。
final class DNSBlocklistLoaderTests: XCTestCase {

    func test_effectiveBlocklist_unionsCuratedAndSelf() {
        let list = DNSBlocklistLoader.effectiveBlocklist(
            curated: ["doubleclick.net"], selfReported: ["myad.example.com"])
        XCTAssertTrue(list.isBlocked("x.doubleclick.net"), "curated が効く")
        XCTAssertTrue(list.isBlocked("myad.example.com"), "self-reported が効く")
    }

    func test_effectiveBlocklist_selfReportedAloneWorks() {
        let list = DNSBlocklistLoader.effectiveBlocklist(
            curated: [], selfReported: ["reported.example.com"])
        XCTAssertTrue(list.isBlocked("reported.example.com"))
        XCTAssertFalse(list.isBlocked("example.com"))
    }

    func test_effectiveBlocklist_empty_blocksNothing() {
        let list = DNSBlocklistLoader.effectiveBlocklist(curated: [], selfReported: [])
        XCTAssertFalse(list.isBlocked("anything.example.com"))
        XCTAssertEqual(list.count, 0)
    }
}
