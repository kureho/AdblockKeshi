import XCTest
@testable import AdblockKeshi

/// v4.2.0 報告種別（広告が消えない / サイトが壊れた）のフォーム契約。
///
/// 壊れ報告は
///   - 広告の種類（ad_type）を要求しない（壊れ方は広告タイプでは表せない）
///   - サーバへ report_kind=site_broken で送る（サーバは広告集約の母集団から隔離する）
///   - 成功時に「どのサイトか（host）」を画面へ渡す（Safari なら「このサイトで一時オフ」を提示）
/// を固定する。
@MainActor
final class ReportFormViewModelKindTests: XCTestCase {

    private final class CaptureClient: ReportAPIClientProtocol, @unchecked Sendable {
        var lastAdType: AdType?
        var lastKind: ReportKind?
        var submitCount = 0

        func submitReport(url: URL, memo: String?, adType: AdType?, reportKind: ReportKind,
                          seenIn: SeenIn, diagnostics: ReportDiagnostics) async throws {
            submitCount += 1
            lastAdType = adType
            lastKind = reportKind
        }

        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {}
    }

    private func makeViewModel(
        client: ReportAPIClientProtocol,
        onSuccess: @escaping (ReportSuccess) -> Void = { _ in }
    ) -> ReportFormViewModel {
        ReportFormViewModel(apiClient: client, historyStore: nil,
                            diagnosticsCollector: nil, onSuccess: onSuccess)
    }

    func test_defaultKind_isAdNotBlocked() {
        let vm = makeViewModel(client: CaptureClient())
        XCTAssertEqual(vm.selectedKind, .adNotBlocked, "既定は従来の広告報告（主用途を変えない）")
    }

    func test_adReport_stillRequiresAdType() {
        let vm = makeViewModel(client: CaptureClient())
        vm.urlInput = "https://example.com/article"
        vm.selectedSeenIn = .safari
        XCTAssertFalse(vm.canSubmit, "広告報告は従来どおり広告の種類が必須")
        vm.selectedAdType = .popup
        XCTAssertTrue(vm.canSubmit)
    }

    func test_brokenReport_doesNotRequireAdType() {
        let vm = makeViewModel(client: CaptureClient())
        vm.selectedKind = .siteBroken
        vm.urlInput = "https://example.com/article"
        vm.selectedSeenIn = .safari
        XCTAssertNil(vm.selectedAdType)
        XCTAssertTrue(vm.canSubmit, "壊れ報告は広告の種類なしで送信できる")
    }

    func test_brokenReport_sendsSiteBrokenKind_andNilAdType() async {
        let client = CaptureClient()
        let vm = makeViewModel(client: client)
        vm.selectedKind = .siteBroken
        vm.selectedAdType = .popup   // 種別切替前に選んでいた残骸があっても
        vm.urlInput = "https://example.com/article"
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertEqual(client.lastKind, .siteBroken)
        XCTAssertNil(client.lastAdType, "壊れ報告に広告タイプを混ぜない（サーバの解釈を汚さない）")
        XCTAssertEqual(client.submitCount, 1)
    }

    func test_adReport_sendsAdNotBlockedKind() async {
        let client = CaptureClient()
        let vm = makeViewModel(client: client)
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertEqual(client.lastKind, .adNotBlocked)
        XCTAssertEqual(client.lastAdType, .interstitial)
    }

    func test_success_carriesKindSeenInAndHost() async {
        var success: ReportSuccess?
        let vm = makeViewModel(client: CaptureClient(), onSuccess: { success = $0 })
        vm.selectedKind = .siteBroken
        vm.urlInput = "https://News.Example.com/article?x=1"
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertEqual(success?.kind, .siteBroken)
        XCTAssertEqual(success?.seenIn, .safari)
        XCTAssertEqual(success?.host, "news.example.com",
                       "一時オフの対象 host（小文字化済み）を送信完了画面へ渡す")
    }

    func test_success_resetsKindToDefault() async {
        let vm = makeViewModel(client: CaptureClient())
        vm.selectedKind = .siteBroken
        vm.urlInput = "https://example.com/a"
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")
        XCTAssertEqual(vm.selectedKind, .adNotBlocked, "次の報告は既定の広告報告から")
    }

    /// 「このサイトで一時オフ」の提示条件: Safari の壊れ報告のみ
    /// （Safari 以外＝Content Blocker の例外では直らない。DNS は一時停止で対処）。
    func test_reportSuccess_offersSiteException_onlyForSafariBrokenReport() {
        func success(_ kind: ReportKind, _ seenIn: SeenIn) -> ReportSuccess {
            ReportSuccess(kind: kind, seenIn: seenIn, host: "a.example.com")
        }
        XCTAssertTrue(success(.siteBroken, .safari).offersSiteException)
        XCTAssertFalse(success(.siteBroken, .otherApp).offersSiteException)
        XCTAssertFalse(success(.adNotBlocked, .safari).offersSiteException)
        XCTAssertFalse(success(.adNotBlocked, .otherApp).offersSiteException)
    }
}
