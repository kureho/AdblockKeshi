import XCTest
import WebKit
@testable import AdblockKeshi

/// v3.3.0 L2 アグレッシブルール（url-filter:".*" + load-type:third-party + if-domain + ignore-previous-rules）が
/// WebKit Content Blocker コンパイラに実際に受理されることを runtime で検証する。
/// 不受理だと popunder Extension のルールリスト全体が load 失敗する（all-or-nothing）ため、提出前の要となる検証。
@MainActor
final class PopunderRuleCompileTests: XCTestCase {

    func test_L2_aggressive_rule_compiles_in_webkit() async throws {
        // L2 の代表形（block 全 third-party script → allow を ignore-previous-rules）
        let rules: [[String: Any]] = [
            [
                "trigger": [
                    "url-filter": ".*",
                    "resource-type": ["script"],
                    "load-type": ["third-party"],
                    "if-domain": ["*tokyomotion.net"],
                ],
                "action": ["type": "block"],
            ],
            [
                "trigger": [
                    "url-filter": "^[^:]+://+([^:/]+\\.)?fluidplayer\\.com[/:]",
                    "if-domain": ["*tokyomotion.net"],
                ],
                "action": ["type": "ignore-previous-rules"],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: rules)
        let json = String(data: data, encoding: .utf8)!

        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let list = try await store.compileContentRuleList(
            forIdentifier: "popunder-l2-compile-test",
            encodedContentRuleList: json
        )
        XCTAssertNotNil(list, "WebKit が L2 アグレッシブルールのコンパイルに失敗した")
    }

    /// 出荷する popunder-rules.json「全体」（L1 + streamtape/tokyomotion の L2 含む）が
    /// WebKit Content Blocker コンパイラに丸ごと受理されることを検証する（Phase 4-B）。
    /// 1 ルールでも不正だと全体 load 失敗（all-or-nothing）になるため、提出前の要となる検証。
    func test_full_popunder_rules_json_compiles_in_webkit() async throws {
        // リポジトリ内の出荷 JSON を #filePath 起点で読む（Tests/ → repo ルート → PopunderBlockerExtension/...）。
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let rulesURL = repoRoot
            .appendingPathComponent("PopunderBlockerExtension/Resources/popunder-rules.json")
        let json = try String(contentsOf: rulesURL, encoding: .utf8)

        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let list = try await store.compileContentRuleList(
            forIdentifier: "popunder-full-compile-test",
            encodedContentRuleList: json
        )
        XCTAssertNotNil(list, "出荷 popunder-rules.json 全体の WebKit コンパイルに失敗した")
    }

    /// 報告反映の combined（出荷 popunder-rules.json 全体 + 安全化 reported を最後尾に splice）が
    /// WebKit でコンパイルできることを検証（報告ルール再配置）。reported は third-party/document 除外の host-block。
    /// 注: これは compile（受理）の検証であり、ランタイム順序（reported が L2 ipr の後ろで有効）は実機検証(Phase 6)。
    func test_popunder_combined_with_reported_compiles_in_webkit() async throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let baseURL = repoRoot
            .appendingPathComponent("PopunderBlockerExtension/Resources/popunder-rules.json")
        let baseData = try Data(contentsOf: baseURL)
        let reported = [
            try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://ads.example.com/")),
            try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://tracker.test/")),
        ]
        let combined = try CombinedRuleListMerge.splice(standardJSON: baseData, appending: reported)
        let json = String(data: combined, encoding: .utf8)!

        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let list = try await store.compileContentRuleList(
            forIdentifier: "popunder-combined-reported-compile-test",
            encodedContentRuleList: json
        )
        XCTAssertNotNil(list, "popunder L1+L2 + reported の combined の WebKit コンパイルに失敗した")
    }
}
