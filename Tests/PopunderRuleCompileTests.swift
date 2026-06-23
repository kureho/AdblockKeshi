import XCTest
import WebKit

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
}
