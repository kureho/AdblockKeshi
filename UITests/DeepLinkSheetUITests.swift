import XCTest

/// リンクが届いた時に、開いている画面が行き先を隠さないことの実測（D-150・仕様 a146-paywall-link-spec.md 4 周目）。
/// 入口は本物のリンク（`XCUIDevice.shared.system.open` → SpringBoard の確認 → `onOpenURL`）。
/// - 見るだけの画面（説明シート・押し込んだ購入画面）: ①行き先が見える ②閉じたはずの画面が残らない
/// - 未対応の URL では何も閉じない（決まり 1）
/// - 書きかけの報告フォーム: ③リンクの後も入力が残る
final class DeepLinkSheetUITests: XCTestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func open(_ link: String) {
        XCUIDevice.shared.system.open(URL(string: link)!)
        let button = springboard.buttons.matching(
            NSPredicate(format: "label IN {'開く', 'Open'}")
        ).firstMatch
        if button.waitForExistence(timeout: 5) { button.tap() }
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    private func waitSelected(_ el: XCUIElement, _ message: String) {
        let p = NSPredicate(format: "isSelected == true")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: p, evaluatedWith: el)], timeout: 8),
                       .completed, message)
    }

    // MARK: 決まり 1: 未対応の URL では購入画面を閉じない

    @MainActor
    func test_未対応のリンクでは購入画面が閉じない() {
        let app = launch(["--show-settings-tab"])
        let card = app.buttons["settingsProCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "設定の購入カードが無い")
        card.tap()
        let close = app.buttons["paywallSheetClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "購入画面が開かない")

        open("adblockkeshi://unknown")
        sleep(2)
        XCTAssertTrue(close.exists, "未対応のリンクで購入画面が閉じた（決まり 1 違反）")
    }

    // MARK: 見るだけの説明シート（準備中画面）

    @MainActor
    func test_説明シートはリンクで閉じて行き先が見える() {
        let app = launch(["--force-disabled", "--show-filter-sheet"])
        let sheetBar = app.navigationBars["フィルタについて"]
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 10), "説明シートが開かない")

        open("adblockkeshi://report")
        waitSelected(app.tabBars.buttons["報告"], "報告タブに切り替わらない")
        XCTAssertTrue(app.buttons["広告を報告する"].waitForExistence(timeout: 8), "①行き先（報告）が見えない")
        XCTAssertTrue(sheetBar.waitForNonExistence(timeout: 8), "①行き先の上に説明シートが残っている")

        // ② 行き先を離れて戻っても、閉じたはずの説明シートが残っていない
        app.tabBars.buttons["ブロッカー"].tap()
        XCTAssertFalse(sheetBar.waitForExistence(timeout: 2), "②戻ると説明シートが残っている")
    }

    // MARK: 押し込んだ購入画面（ブロッカータブ）

    @MainActor
    func test_押し込んだ購入画面はhomeのリンクで戻る() {
        let app = launch(["--force-enabled"])
        let completed = app.staticTexts["広告ブロック中"]
        XCTAssertTrue(completed.waitForExistence(timeout: 10), "完了画面が出ない")
        let entry = app.staticTexts["アプリ内広告ブロック"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "購入の入口カードが無い")
        entry.tap()
        let pushedBar = app.navigationBars["アプリ内広告ブロック"]
        XCTAssertTrue(pushedBar.waitForExistence(timeout: 8), "購入画面が押し込まれない")

        open("adblockkeshi://home")
        XCTAssertTrue(pushedBar.waitForNonExistence(timeout: 8), "①②home のリンクの後も押し込んだ購入画面が残っている")
        XCTAssertTrue(completed.isHittable, "①行き先（ブロッカーの画面）が見えない")
    }

    // MARK: 押し込んだ画面（設定タブ）

    @MainActor
    func test_設定に押し込んだ画面はsettingsのリンクで戻る() {
        let app = launch(["--show-settings-tab"])
        let about = app.buttons["このアプリについて"]
        XCTAssertTrue(about.waitForExistence(timeout: 10), "設定の「このアプリについて」が無い")
        app.swipeUp()
        about.tap()
        let pushedBar = app.navigationBars["このアプリについて"]
        XCTAssertTrue(pushedBar.waitForExistence(timeout: 8), "このアプリについて が押し込まれない")

        open("adblockkeshi://settings")
        XCTAssertTrue(pushedBar.waitForNonExistence(timeout: 8), "①②settings のリンクの後も押し込んだ画面が残っている")
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5), "①行き先（設定）が見えない")
    }

    // MARK: 書きかけの報告フォームは閉じない

    @MainActor
    func test_報告フォームの入力はリンクの後も残る() {
        let app = launch(["--show-report-tab"])
        let cta = app.buttons["広告を報告する"]
        XCTAssertTrue(cta.waitForExistence(timeout: 8), "報告タブの入口が無い")
        cta.tap()
        let url = app.textFields.firstMatch
        XCTAssertTrue(url.waitForExistence(timeout: 5), "URL 欄が無い")
        url.tap()
        url.typeText("https://example.com/ad")

        open("adblockkeshi://home")
        waitSelected(app.tabBars.buttons["ブロッカー"], "ブロッカータブに切り替わらない")

        app.tabBars.buttons["報告"].tap()
        let again = app.textFields.firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 5), "③報告フォームが閉じている")
        XCTAssertEqual(again.value as? String, "https://example.com/ad", "③打ち込んだ URL が消えている")
    }
}
