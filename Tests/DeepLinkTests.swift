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
        XCTAssertTrue(root.contains("DeepLink.announceArrival(at: tab)"),
                      "リンクの到着を、開いているシートへ知らせていない")
        // 決まり 1: 知らせは「行き先が分かった」後だけ（未対応の URL では何も閉じない）。
        let guardIndex = try XCTUnwrap(root.range(of: "guard let tab = DeepLink.tab(for: url) else { return }"),
                                       "未対応の URL を弾く guard が無い")
        let announceIndex = try XCTUnwrap(root.range(of: "DeepLink.announceArrival(at: tab)"))
        XCTAssertLessThan(guardIndex.lowerBound, announceIndex.lowerBound,
                          "知らせが、行き先の判定より前に出ている（決まり 1 違反）")
    }

    func test_購入画面がリンク到着で閉じる() throws {
        let paywall = try source("App/Pro/ProPaywallSheet.swift")
        XCTAssertNotNil(paywall.firstMatch(of: #/publisher\(for: DeepLink\.didArrive\)\) \{ _ in\s*dismiss\(\)\s*\}/#),
                        "購入画面がリンクの到着で閉じない")
    }
}
