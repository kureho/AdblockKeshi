import XCTest
import KurehoKit
@testable import AdblockKeshi

/// 購入画面（22 本共通の対比表）の文言検査。
final class ProCatalogTests: XCTestCase {

    /// 列からはみ出す長さの語を置いていないか（値 7 字 / 名前 10 字）。
    func testRowsFitInColumns() {
        XCTAssertTrue(PaywallCopyAudit.violations(in: ProCatalog.rows).isEmpty,
                      "\(PaywallCopyAudit.violations(in: ProCatalog.rows))")
    }

    /// 注記に二重空白や「、 」が混ざっていないか。
    func testPaymentNoteHasNoStrayWhitespace() {
        XCTAssertTrue(PaywallCopyAudit.noteViolations(in: ProCatalog.paymentNote).isEmpty)
    }

    /// 買って増えるのは**他アプリの広告**だけ（実際にゲートしているのは `DNSSettingsView` の 1 つ）。
    /// ★表を厚く見せるために「左右が同じ行」を足さない（共通部品の検査も同じことを弾く）。
    func testOnlyInAppBlockingIsSold() {
        XCTAssertEqual(ProCatalog.rows.count, 1)
        XCTAssertEqual(ProCatalog.rows.first?.symbol, "apps.iphone")
        XCTAssertNotEqual(ProCatalog.rows.first?.free, ProCatalog.rows.first?.plus)
    }

    /// 買い切りだと言い切る。
    func testPaymentNoteSaysOneTimePurchase() {
        XCTAssertTrue(ProCatalog.paymentNote.contains("1 回だけ"))
    }

    /// ★**おさえられない先を買う前に書く**（訴求規律・旧 `limitsNote` を注記へ畳んだ）。
    func testPaymentNoteKeepsTheLimitDisclosure() {
        for app in ["YouTube", "X", "Instagram"] {
            XCTAssertTrue(ProCatalog.paymentNote.contains(app), "\(app) の限界表記が消えている")
        }
    }

    /// 無料のままできることを先に言う。
    func testFreeSummaryMentionsSafari() {
        XCTAssertTrue(ProCatalog.freeSummary.contains("Safari"))
    }
}
