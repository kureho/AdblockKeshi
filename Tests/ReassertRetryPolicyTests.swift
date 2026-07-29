import XCTest
@testable import AdblockKeshi

/// v4.0.1 回帰テスト: Wi-Fi join 直後は DHCP で DNS が configure されるまで数秒〜十数秒かかる。
/// reassert の snapshot リトライ予算が短すぎると、日常の Wi-Fi 切替でトンネルが自動停止し
/// トグルが勝手に OFF になる（2026-07-29 実機 KPhone で 2 秒予算の枯渇を実測）。
final class ReassertRetryPolicyTests: XCTestCase {

    func test_totalBudget_coversSlowWifiDHCP() {
        let total = Double(ReassertRetryPolicy.maxAttempts) * ReassertRetryPolicy.interval
        XCTAssertGreaterThanOrEqual(total, 30.0,
            "Wi-Fi DHCP の遅延（十数秒）を吸収できる予算にする（実測: 2 秒では日常切替で枯渇）")
    }

    func test_interval_staysResponsive() {
        XCTAssertLessThanOrEqual(ReassertRetryPolicy.interval, 1.0,
            "DNS が取れ次第すぐ再適用できるよう間隔は 1 秒以下に保つ")
        XCTAssertGreaterThan(ReassertRetryPolicy.interval, 0, "busy loop 防止")
    }
}
