import XCTest
@testable import AdblockKeshi

/// D-lite の報告フォーム契約。
///
/// 報告は「ブロック対象の指定」ではなく **「広告が消えなかったページ」の改善用データ**。
/// したがって
///   - どこで見たか（`seen_in`）の選択が必須
///   - yahoo.co.jp 等の保護ドメインも**正常に送信できる**（送信前ガードは廃止）
///   - 送信しても、その端末で即ブロックはしない
/// を固定する。
@MainActor
final class ReportFormViewModelDLiteTests: XCTestCase {

    private final class CaptureClient: ReportAPIClientProtocol, @unchecked Sendable {
        var lastURL: URL?
        var lastAdType: AdType?
        var lastSeenIn: SeenIn?
        var lastDiagnostics: ReportDiagnostics?
        var submitCount = 0

        func submitReport(url: URL, memo: String?, adType: AdType?, reportKind: ReportKind,
                          seenIn: SeenIn, diagnostics: ReportDiagnostics) async throws {
            submitCount += 1
            lastURL = url
            lastAdType = adType
            lastSeenIn = seenIn
            lastDiagnostics = diagnostics
        }

        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {}
    }

    private struct StubCollector: ReportDiagnosticsCollecting {
        let value: ReportDiagnostics
        func collect() async -> ReportDiagnostics { value }
    }

    private func makeViewModel(
        client: ReportAPIClientProtocol,
        history: LocalReportHistoryStore? = nil,
        collector: ReportDiagnosticsCollecting? = nil,
        onSuccess: @escaping (ReportSuccess) -> Void = { _ in }
    ) -> ReportFormViewModel {
        ReportFormViewModel(
            apiClient: client,
            historyStore: history,
            diagnosticsCollector: collector,
            onSuccess: onSuccess
        )
    }

    // MARK: - seen_in

    func test_canSubmit_isFalse_whenSeenInNotSelected() {
        let vm = makeViewModel(client: CaptureClient())
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        XCTAssertNil(vm.selectedSeenIn)
        XCTAssertFalse(vm.canSubmit, "どこで見たかを選ぶまで送信不可")
    }

    func test_canSubmit_isTrue_whenURLAdTypeAndSeenInSelected() {
        let vm = makeViewModel(client: CaptureClient())
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        vm.selectedSeenIn = .safari
        XCTAssertTrue(vm.canSubmit)
    }

    func test_completeSubmit_passesSeenInToClient_andResetsIt() async {
        let client = CaptureClient()
        var succeededWith: SeenIn?
        let vm = makeViewModel(client: client, onSuccess: { succeededWith = $0.seenIn })
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .popup
        vm.selectedSeenIn = .otherApp
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertEqual(client.lastSeenIn, .otherApp)
        XCTAssertEqual(succeededWith, .otherApp, "送信後の画面はどこで見たかに応じて出し分ける")
        XCTAssertNil(vm.selectedSeenIn, "次の報告のためにリセットする")
    }

    // MARK: - 案 A（保護ドメインの送信前ガード）の撤去

    func test_criticalDomain_hasNoURLError() {
        let vm = makeViewModel(client: CaptureClient())
        vm.urlInput = "https://www.yahoo.co.jp/"
        XCTAssertNil(vm.urlError, "閲覧ページとして yahoo.co.jp を報告するのは正常な操作")
    }

    func test_criticalDomain_canSubmit() {
        let vm = makeViewModel(client: CaptureClient())
        vm.urlInput = "https://www.apple.com/jp/"
        vm.selectedAdType = .stickyBanner
        vm.selectedSeenIn = .safari
        XCTAssertTrue(vm.canSubmit, "保護ドメインでもクライアントで弾かない（サーバも受理する）")
    }

    func test_criticalDomain_isActuallySubmitted() async {
        let client = CaptureClient()
        let vm = makeViewModel(client: client)
        vm.urlInput = "https://www.yahoo.co.jp/news"
        vm.selectedAdType = .interstitial
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertEqual(client.submitCount, 1)
        XCTAssertEqual(client.lastURL?.absoluteString, "https://www.yahoo.co.jp/news")
    }

    // MARK: - 診断情報

    func test_completeSubmit_attachesCollectedDiagnostics() async {
        let client = CaptureClient()
        let collector = StubCollector(value: ReportDiagnostics(
            blockerEnabled: false,
            dnsEnabled: true,
            appVersion: "4.1.0",
            appBuild: "10004",
            filterVersion: "2026-08-01"
        ))
        let vm = makeViewModel(client: client, collector: collector)
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .popup
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertEqual(client.lastDiagnostics?.blockerEnabled, false)
        XCTAssertEqual(client.lastDiagnostics?.dnsEnabled, true)
        XCTAssertEqual(client.lastDiagnostics?.appVersion, "4.1.0")
    }

    /// ★最重要: 診断情報が 1 つも取れなくても報告は成功する。
    func test_diagnosticsUnavailable_stillSubmitsSuccessfully() async {
        let client = CaptureClient()
        var didSucceed = false
        let vm = makeViewModel(
            client: client,
            collector: StubCollector(value: .unavailable),
            onSuccess: { _ in didSucceed = true }
        )
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .popup
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertTrue(didSucceed, "診断が取れないから報告できない、は本末転倒")
        XCTAssertEqual(client.submitCount, 1)
        XCTAssertEqual(client.lastDiagnostics, .unavailable)
        XCTAssertEqual(vm.state, .idle, "診断の欠落をエラー表示しない")
    }

    func test_noCollectorInjected_sendsUnavailableDiagnostics() async {
        let client = CaptureClient()
        let vm = makeViewModel(client: client, collector: nil)
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .popup
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertEqual(client.lastDiagnostics, .unavailable)
    }

    // MARK: - 履歴

    func test_history_isAlwaysPending_neverAppliedLocally() async {
        let history = LocalReportHistoryStore(defaults: makeIsolatedDefaults())
        let vm = makeViewModel(client: CaptureClient(), history: history)
        vm.urlInput = "https://ads.example.com/banner"
        vm.selectedAdType = .popup
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertEqual(history.items.first?.status, .pending,
                       "D-lite では端末即反映が無いので常に受付済")
        XCTAssertNil(history.items.first?.appliedAt)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "dlite.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
