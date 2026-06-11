import XCTest

/// 報告フォームのレイアウト・キーボード操作の回帰テスト。
/// 2026-06-11 のバグ報告 2 件をカバーする:
/// 1. 長い URL を入力すると UITextField が行幅を突き破り「貼り付け」ボタンが画面外に出る
/// 2. メモ欄 (複数行 TextField) のキーボードを閉じる手段が無く送信ボタンが押せない
final class ReportFormUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchToReportForm() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--show-report-tab"]
        app.launch()
        let cta = app.buttons["広告を報告する"]
        XCTAssertTrue(cta.waitForExistence(timeout: 5), "報告タブの CTA が見つからない")
        cta.tap()
        return app
    }

    func testLongURLKeepsPasteButtonOnScreen() throws {
        let app = launchToReportForm()

        let urlField = app.textFields.firstMatch
        XCTAssertTrue(urlField.waitForExistence(timeout: 5), "URL 入力欄が見つからない")
        urlField.tap()
        urlField.typeText("https://www.example-long-domain.com/search?search_query=somethinglong&search_type=videos&padding=1234567890abcdefg")

        let pasteButton = app.buttons["貼り付け"]
        XCTAssertTrue(pasteButton.exists, "貼り付けボタンが存在しない")
        XCTAssertTrue(pasteButton.isHittable, "貼り付けボタンが画面外に押し出されている (URL 欄のはみ出し)")
        XCTAssertLessThanOrEqual(
            urlField.frame.maxX, app.frame.maxX,
            "URL 入力欄が画面幅からはみ出している"
        )
    }

    func testMemoKeyboardCanBeDismissedAndSubmitReachable() throws {
        let app = launchToReportForm()

        // axis: .vertical の TextField は OS により textField / textView どちらにも
        // なり得るため placeholder で引く
        let memo = app.descendants(matching: .any)
            .matching(NSPredicate(format: "placeholderValue == %@", "例: 動画上のオーバーレイ"))
            .firstMatch
        XCTAssertTrue(memo.waitForExistence(timeout: 5), "メモ欄が見つからない")
        memo.tap()
        memo.typeText("画面内リンクを押すと勝手に遷移されてしまう")

        let done = app.buttons["完了"]
        XCTAssertTrue(done.waitForExistence(timeout: 3), "キーボードツールバーの完了ボタンが無い")
        done.tap()

        // キーボードが閉じたこと (ソフトウェアキーボード表示時のみ判定可能)
        let keyboardGone = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        XCTAssertTrue(keyboardGone, "完了を押してもキーボードが閉じない")

        let submit = app.buttons["送信"]
        XCTAssertTrue(submit.waitForExistence(timeout: 3), "送信ボタンが見つからない")
        app.swipeUp()
        XCTAssertTrue(submit.isHittable, "送信ボタンが押せない")
    }
}
