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
}
