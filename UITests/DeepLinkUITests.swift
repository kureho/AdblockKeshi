import XCTest

/// ディープリンク（`adblockkeshi://report` 等）でタブが切り替わることの実測
/// （C-88・アプリ内イベントの deepLink 受け口）。
///
/// カスタムスキームを外から開くと SpringBoard が「"広告消し" で開きますか?」の確認を
/// 挟むため、`simctl openurl` 単体では検証が完結しない。ここでダイアログをタップして通す。
/// ボタンのラベルは OS 言語に依存するので ja/en 両対応の述語で探す。
final class DeepLinkUITests: XCTestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func confirmOpenIfAsked() {
        let open = springboard.buttons.matching(
            NSPredicate(format: "label IN {'開く', 'Open'}")
        ).firstMatch
        if open.waitForExistence(timeout: 5) {
            open.tap()
        }
    }

    /// 前の実行が確認ダイアログを残していたら片付ける（残留ダイアログは後続を汚す）。
    private func dismissLeftoverDialog() {
        let cancel = springboard.buttons.matching(
            NSPredicate(format: "label IN {'キャンセル', 'Cancel'}")
        ).firstMatch
        if cancel.waitForExistence(timeout: 2) {
            cancel.tap()
        }
    }

    private func assertTabSelected(_ tab: XCUIElement, _ message: String) {
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "タブバーに \(tab.label) が見つからない")
        let selected = NSPredicate(format: "isSelected == true")
        let result = XCTWaiter().wait(
            for: [expectation(for: selected, evaluatedWith: tab)],
            timeout: 8
        )
        XCTAssertEqual(result, .completed, message)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func test_deepLinkでタブが切り替わる() {
        dismissLeftoverDialog()

        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.tabBars.buttons["ブロッカー"].waitForExistence(timeout: 8),
            "起動直後にタブバーが表示されない"
        )

        // ① フォアグラウンド受信: 報告タブへ
        XCUIDevice.shared.system.open(URL(string: "adblockkeshi://report")!)
        confirmOpenIfAsked()
        assertTabSelected(app.tabBars.buttons["報告"],
                          "adblockkeshi://report で報告タブに切り替わらない")
        attach(app, name: "deeplink-report")

        // ② コールドスタート（アプリ内イベントからの主経路）: 設定タブへ。
        //    直前に報告へ移した状態から切り替わることで、起動時の受け取りを実証する。
        app.terminate()
        XCUIDevice.shared.system.open(URL(string: "adblockkeshi://settings")!)
        confirmOpenIfAsked()
        assertTabSelected(app.tabBars.buttons["設定"],
                          "コールドスタートの adblockkeshi://settings で設定タブに切り替わらない")
        attach(app, name: "deeplink-coldstart-settings")
    }
}
