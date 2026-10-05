import XCTest
@testable import AdblockKeshi

/// 基本保護の combined（標準 + 一時オフ）は、アプリ本体で組み立てる。標準ルールの同梱は基本保護の拡張
/// （ContentBlockerExtension.appex）の中にあり、アプリ本体（Bundle.main）の直下には無い。
/// App Group のファイルが無い（同梱と同じ中身なので記録だけした新規インストール）・大きすぎて使えない
/// （4.4.1 以前の 27.6MB が残った端末）ときに同梱を見つけられないと、基本保護の combined を消してしまい、
/// 一時オフが効かなくなる（Codex 指摘 2026-10-05）。
final class CombinedRuleListCoordinatorStandardRulesTests: XCTestCase {

    func test_standard_rules_bundle_contains_every_basic_variant() {
        let bundle = CombinedRuleListCoordinator.standardRulesBundle()
        for name in ["merged-rules", "ad-rules", "security-rules", "empty-rules"] {
            XCTAssertNotNil(bundle.url(forResource: name, withExtension: "json"), name)
        }
    }
}
