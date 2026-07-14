import XCTest
@testable import AdblockKeshi

/// DNSCriticalGuard（保護ドメインは絶対にブロックしない・層3）のテスト。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §fail-open 層3
final class DNSCriticalGuardTests: XCTestCase {

    func test_criticalDomains_neverBlocked_includingGithubIO() {
        XCTAssertTrue(DNSCriticalGuard.isCritical("push.apple.com"))       // 既存 critical のサブドメイン
        XCTAssertTrue(DNSCriticalGuard.isCritical("apple.com"))            // 完全一致
        XCTAssertTrue(DNSCriticalGuard.isCritical("kureho.github.io"))     // self-fetch 先（自己更新経路を守る）
        XCTAssertTrue(DNSCriticalGuard.isCritical("api.example.github.io"))// github.io サブドメイン
        XCTAssertFalse(DNSCriticalGuard.isCritical("ads.example.com"))     // 通常ドメインは対象外
        XCTAssertFalse(DNSCriticalGuard.isCritical("notgithub.io"))        // 前方一致は保護しない
    }

    func test_inheritsReportFastlaneCriticalList() {
        // レポート fastlane 側の critical はすべて DNS 側でも保護される（単一ソース継承）
        for d in CriticalDomainGuard.criticalDomains {
            XCTAssertTrue(DNSCriticalGuard.isCritical(d), "\(d) は DNS 側でも critical であるべき")
        }
    }
}
