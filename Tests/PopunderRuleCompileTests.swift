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

    /// P2 回帰防止（両トグルOFF が効かない）: empty-rules の no-op は WebKit コンパイル成功、
    /// 旧 "[]" は失敗することを検証する。空配列は content blocker で不正なため、OFF 時に "[]" を
    /// 渡すと reload compile が失敗して旧ルールが残る＝OFF が効かなかった。
    func test_empty_noOp_rule_compiles_but_empty_array_fails() async throws {
        let store = try XCTUnwrap(WKContentRuleListStore.default())
        // 新 empty-rules 相当の no-op（有効・何もブロックしない）
        let noOp = #"[{"action":{"type":"ignore-previous-rules"},"trigger":{"url-filter":".*"}}]"#
        let list = try await store.compileContentRuleList(
            forIdentifier: "empty-noop-compile-test",
            encodedContentRuleList: noOp
        )
        XCTAssertNotNil(list, "no-op empty-rules は WebKit コンパイルに成功すべき（OFF が効く）")

        // 旧 "[]" はコンパイル失敗すべき（OFF が効かなかった原因）
        do {
            _ = try await store.compileContentRuleList(
                forIdentifier: "empty-array-compile-test",
                encodedContentRuleList: "[]"
            )
            XCTFail("空配列 [] は content blocker で不正なのでコンパイル失敗すべき")
        } catch {
            // 期待通り throw（[] は不正）
        }
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
