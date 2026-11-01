import XCTest

/// A-162（2026-11-01 kureho 案1b）: 報告タブの一番下の「報告は完全匿名」の 1 行を外す。
/// 報告には URL のほか、端末ごとの番号・報告と広告の種類・診断情報も届くため「完全匿名」は実態と合わない。
/// 送る物はストアの説明文に全部書く（画面に新しい文は足さない）。上の説明文は今のまま残す。
final class ReportEntryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReportTabDoesNotClaimAnonymity() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--show-report-tab"]
        app.launch()

        let cta = app.buttons["広告を報告する"]
        XCTAssertTrue(cta.waitForExistence(timeout: 5), "報告タブの CTA が見つからない")
        // 一番下のカードまで出ているのを先に確かめる（「無い」の判定が画面違いで空振りしないように）
        XCTAssertTrue(app.staticTexts["送信後のながれ"].waitForExistence(timeout: 5),
                      "送信後のながれのカードが見つからない")
        XCTAssertTrue(app.staticTexts["URL を送信するだけ。内容を確認して、消せる広告はブロックに反映します。"].exists,
                      "上の説明文は今のまま残す")

        let anonymityClaims = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "匿名"))
        XCTAssertEqual(anonymityClaims.count, 0, "報告タブに「匿名」をうたう文が残っている")
    }
}
