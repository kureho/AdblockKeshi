import XCTest
@testable import AdblockKeshi

/// ディープリンク（`adblockkeshi://<タブ名>`）をタブへ解決するパーサのテスト。
/// アプリ内イベント（ASC）の deepLink 必須要件（C-88）の受け口。
final class DeepLinkTests: XCTestCase {

    func test_ホームのリンクはブロッカータブに解決される() {
        XCTAssertEqual(DeepLink.tab(for: URL(string: "adblockkeshi://home")!), .blocker)
    }

    func test_報告のリンクは報告タブに解決される() {
        XCTAssertEqual(DeepLink.tab(for: URL(string: "adblockkeshi://report")!), .report)
    }

    func test_設定のリンクは設定タブに解決される() {
        XCTAssertEqual(DeepLink.tab(for: URL(string: "adblockkeshi://settings")!), .settings)
    }

    func test_ホスト大文字でも解決される() {
        XCTAssertEqual(DeepLink.tab(for: URL(string: "adblockkeshi://Settings")!), .settings)
    }

    func test_別スキームは無視される() {
        XCTAssertNil(DeepLink.tab(for: URL(string: "https://example.com/report")!))
    }

    func test_未知のホストは無視される() {
        XCTAssertNil(DeepLink.tab(for: URL(string: "adblockkeshi://nazo")!))
    }
}
