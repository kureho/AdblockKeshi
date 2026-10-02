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

    // MARK: - 購入画面の取り残し防止（電光掲示板 1.0.1 と同じ漏れ）

    /// リンク到着時に設定タブが持つ購入画面が開いたままだと、タブ切替が購入画面の下で起きるだけで
    /// 行き先が見えない。受けて閉じる処理は共通の `ProPaywallSheet` に置き、
    /// ルートが到着を通知することをソースで固定する。
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func test_リンク到着をルートが通知している() throws {
        let root = try source("App/AdblockKeshiApp.swift")
        XCTAssertTrue(root.contains("NotificationCenter.default.post(name: DeepLink.didArrive"),
                      "リンクの到着を、開いているシートへ知らせていない")
    }

    func test_購入画面がリンク到着で閉じる() throws {
        let paywall = try source("App/Pro/ProPaywallSheet.swift")
        XCTAssertNotNil(paywall.firstMatch(of: #/publisher\(for: DeepLink\.didArrive\)\) \{ _ in\s*dismiss\(\)\s*\}/#),
                        "購入画面がリンクの到着で閉じない")
    }
}
