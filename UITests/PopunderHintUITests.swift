import XCTest

/// A-88 ①: 2 本目（報告反映）が OFF の人に、完了画面で「報告反映も ON に」を案内する。
/// 基本保護に入り切らない広告の残りは 2 本目に載るので、OFF のままだと届かない。
///
/// シミュレータでは報告反映の拡張は常に OFF（Safari の設定で ON にする手段が無い）＝案内が出る側を確かめられる。
/// `--force-enabled` で完了画面を出す（基本保護の実状態は見ない）。
final class PopunderHintUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_報告反映がOFFなら完了画面に案内が出る() {
        let app = XCUIApplication()
        app.launchArguments = ["--force-enabled"]
        app.launch()

        XCTAssertTrue(app.staticTexts["広告ブロック中"].waitForExistence(timeout: 10), "完了画面が出ない")
        let hint = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH '「報告反映」も ON にすると'")
        ).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 8), "報告反映の案内が完了画面に無い")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "completed-with-popunder-hint"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
