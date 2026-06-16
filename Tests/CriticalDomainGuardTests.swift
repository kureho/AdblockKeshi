import XCTest
@testable import AdblockKeshi

/// 自己報告ファストレーンの安全弁。決済/銀行/大手/政府などの重要ドメインは、
/// 誤って報告されても端末でブロックしない（サーバ critical-list.ts と同等の保護を端末側にも持つ）。
final class CriticalDomainGuardTests: XCTestCase {

    func test_exact_match_is_critical() {
        XCTAssertTrue(CriticalDomainGuard.isCritical("stripe.com"))
        XCTAssertTrue(CriticalDomainGuard.isCritical("mizuhobank.co.jp"))
        XCTAssertTrue(CriticalDomainGuard.isCritical("apple.com"))
    }

    func test_subdomain_is_protected() {
        XCTAssertTrue(CriticalDomainGuard.isCritical("pay.stripe.com"))
        XCTAssertTrue(CriticalDomainGuard.isCritical("www.paypal.com"))
    }

    func test_non_critical_is_false() {
        XCTAssertFalse(CriticalDomainGuard.isCritical("ads.example.com"))
        XCTAssertFalse(CriticalDomainGuard.isCritical("ettocrimpycrimpy.com"))
        // suffix が "." 境界でないものは保護対象外（誤検知防止）
        XCTAssertFalse(CriticalDomainGuard.isCritical("notstripe.com"))
    }

    func test_case_insensitive() {
        XCTAssertTrue(CriticalDomainGuard.isCritical("PAY.Stripe.COM"))
    }
}
