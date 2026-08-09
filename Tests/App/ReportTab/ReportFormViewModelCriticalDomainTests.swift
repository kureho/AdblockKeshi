import XCTest
@testable import AdblockKeshi

/// 保護ドメイン（apps.apple.com 等）の URL は送信前にクライアントで弾き、
/// 日本語で理由を説明する。サーバに投げて critical_domain 400 を往復させない
/// （2026-08-09 問い合わせ: 9 回再試行 → 自動 ban の実害が出た）。
@MainActor
final class ReportFormViewModelCriticalDomainTests: XCTestCase {

    private final class NoopClient: ReportAPIClientProtocol, @unchecked Sendable {
        func submitReport(url: URL, memo: String?, adType: AdType?) async throws {}
        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {}
    }

    func test_criticalDomainURL_showsJapaneseGuidance() {
        let vm = ReportFormViewModel(apiClient: NoopClient(), onSuccess: {})
        vm.urlInput = "https://apps.apple.com/jp/app/id123456"
        let error = vm.urlError
        XCTAssertNotNil(error, "保護ドメインはインラインで理由を表示する")
        XCTAssertTrue(error?.contains("報告できません") == true, "日本語の説明であること: \(error ?? "nil")")
        XCTAssertFalse(error?.contains("critical_domain") == true, "技術用語をユーザーに見せない")
    }

    func test_criticalDomainURL_blocksSubmit() {
        let vm = ReportFormViewModel(apiClient: NoopClient(), onSuccess: {})
        vm.urlInput = "https://search.yahoo.co.jp/search?p=x"
        vm.selectedAdType = .interstitial
        XCTAssertFalse(vm.canSubmit, "保護ドメインは送信ボタン自体を無効化する")
    }

    func test_invalidURLTakesPrecedenceOverCriticalDomain() {
        // http:// は URLValidator (https-only) で invalid。critical 判定より
        // 形式エラーを先に出す判定順序を回帰テストとして固定する
        let vm = ReportFormViewModel(apiClient: NoopClient(), onSuccess: {})
        vm.urlInput = "http://apps.apple.com/jp/app/id123456"
        let error = vm.urlError
        XCTAssertNotNil(error)
        XCTAssertNotEqual(error, ReportFormViewModel.criticalDomainMessage,
                          "形式エラーが critical 文言より優先されること")
    }

    func test_normalURL_hasNoErrorAndCanSubmit() {
        let vm = ReportFormViewModel(apiClient: NoopClient(), onSuccess: {})
        vm.urlInput = "https://ads.example.com/landing"
        vm.selectedAdType = .popup
        XCTAssertNil(vm.urlError)
        XCTAssertTrue(vm.canSubmit)
    }
}
