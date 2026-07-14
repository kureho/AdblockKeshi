import XCTest
@testable import AdblockKeshi

/// DNSBlocklist（完全/サフィックス一致 + 上限縮退）のテスト。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §DNSBlocklist
final class DNSBlocklistTests: XCTestCase {

    func test_matches_exactAndSuffix_butNotSubstring() {
        let list = DNSBlocklist(domains: ["ads.example.com", "doubleclick.net"])
        XCTAssertTrue(list.isBlocked("ads.example.com"))       // 完全一致
        XCTAssertTrue(list.isBlocked("x.doubleclick.net"))     // サフィックス一致
        XCTAssertTrue(list.isBlocked("a.b.doubleclick.net"))   // 深いサフィックスも一致
        XCTAssertFalse(list.isBlocked("notdoubleclick.net"))   // 部分文字列は不一致
        XCTAssertFalse(list.isBlocked("example.com"))          // 上位ドメインは不一致
        XCTAssertFalse(list.isBlocked("doubleclick.net.evil.com")) // 前方一致は不一致
    }

    func test_matches_isCaseInsensitive_andIgnoresTrailingDot() {
        let list = DNSBlocklist(domains: ["Ads.Example.com."])
        XCTAssertTrue(list.isBlocked("ADS.example.COM"))
        XCTAssertTrue(list.isBlocked("ads.example.com."))
    }

    func test_capsToLimit_whenOverMemoryBudget() {
        let many = (0..<100).map { "d\($0).example.com" }
        let list = DNSBlocklist(domains: many, maxCount: 10)
        XCTAssertEqual(list.count, 10)  // 上限で縮退（メモリ上限対策）
    }

    func test_emptyDomain_isNeverBlocked() {
        let list = DNSBlocklist(domains: ["ads.example.com"])
        XCTAssertFalse(list.isBlocked(""))
    }
}
