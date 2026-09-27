import XCTest
@testable import AdblockKeshi

/// A-88 進め方6: オンボーディングの経路案内を Apple 公式の経路「設定 →『アプリ』→『Safari』→
/// 『機能拡張』」に合わせる。旧文言は「Safari → 機能拡張」で、実際の一覧から探す起点
/// （「アプリ」）が抜けていた。下のボタン(`UIApplication.openSettingsURLString`)は
/// 「設定 → アプリ → 広告消し」に着地するため、そこから「アプリ」へ 1 つ戻る旨も添える。
final class OnboardingSettingsPathWordingTests: XCTestCase {

    func test_step2Title_followsAppleOfficialPath() {
        let title = OnboardingView.step2Title
        XCTAssertNotEqual(title, "Safari → 機能拡張", "「アプリ」の一段を抜いた旧文言のまま残さない")
        // 「アプリ」→「Safari」→「機能拡張」の順で出現すること。
        let appRange = try? XCTUnwrap(title.range(of: "アプリ"))
        let safariRange = try? XCTUnwrap(title.range(of: "Safari"))
        let extRange = try? XCTUnwrap(title.range(of: "機能拡張"))
        XCTAssertNotNil(appRange); XCTAssertNotNil(safariRange); XCTAssertNotNil(extRange)
        if let a = appRange, let s = safariRange, let e = extRange {
            XCTAssertTrue(a.lowerBound < s.lowerBound && s.lowerBound < e.lowerBound,
                          "「アプリ」→「Safari」→「機能拡張」の順で書くこと")
        }
    }

    func test_step2Detail_explainsGoingBackToAppsListFromOwnSettings() {
        let detail = OnboardingView.step2Detail
        XCTAssertTrue(detail.contains("アプリ"),
                      "自アプリの設定画面から一覧の「アプリ」へ戻る旨を一言添える")
    }
}
