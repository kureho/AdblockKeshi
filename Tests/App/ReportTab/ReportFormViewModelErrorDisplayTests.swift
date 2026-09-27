import XCTest
@testable import AdblockKeshi

/// A-88 ③: 送信失敗時の画面表示が実態と合っているかの回帰テスト。
/// 点検記録 `tasks/report-pipeline-audit-2026-09-27.md` の ③・4 件のうち、
/// ロボット確認(Turnstile)の失敗・時間切れ（`ReportFormView.swift:225-233` →
/// `ReportFormViewModel.swift:93-95`）を固定する。
///
/// 修正前は Turnstile が失敗/タイムアウトしても `cancelTurnstile()` が呼ばれるだけで
/// 状態が黙って `.idle` に戻り、何も表示されなかった（＝「押しても送れない」というFBの正体）。
@MainActor
final class ReportFormViewModelErrorDisplayTests: XCTestCase {

    private final class NeverCalledClient: ReportAPIClientProtocol, @unchecked Sendable {
        func submitReport(url: URL, memo: String?, adType: AdType?, reportKind: ReportKind,
                          seenIn: SeenIn, diagnostics: ReportDiagnostics) async throws {
            XCTFail("Turnstile 失敗時はサーバへ到達しないはず")
        }
        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {
            XCTFail("Turnstile 失敗時はサーバへ到達しないはず")
        }
    }

    /// 常に成功するクライアント（ウォッチドッグが送信完了後に誤発火しないことの検証用）。
    private final class SucceedingClient: ReportAPIClientProtocol, @unchecked Sendable {
        func submitReport(url: URL, memo: String?, adType: AdType?, reportKind: ReportKind,
                          seenIn: SeenIn, diagnostics: ReportDiagnostics) async throws {}
        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {}
    }

    /// `requestToken` が戻らない（＝ `.submitting` のまま止まる）クライアント。
    /// 「送信中に `failTurnstile` を呼んでも状態が変わらない」ことを検証するために使う。
    private final class HangingClient: ReportAPIClientProtocol, @unchecked Sendable {
        func submitReport(url: URL, memo: String?, adType: AdType?, reportKind: ReportKind,
                          seenIn: SeenIn, diagnostics: ReportDiagnostics) async throws {}
        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {
            try? await Task.sleep(for: .seconds(999))
        }
    }

    private func makeAwaitingViewModel() -> ReportFormViewModel {
        let vm = ReportFormViewModel(apiClient: NeverCalledClient(), onSuccess: { _ in })
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        return vm
    }

    /// 1) Turnstile の失敗・30秒タイムアウトは、黙って idle に戻さずエラーとして見せる。
    func test_turnstileFailure_surfacesAsError_insteadOfSilentlyReturningToIdle() {
        let vm = makeAwaitingViewModel()
        XCTAssertEqual(vm.state, .awaitingTurnstile)

        vm.failTurnstile(.turnstileVerificationFailed)

        XCTAssertEqual(
            vm.state, .error(.turnstileVerificationFailed),
            "確認の失敗・時間切れを黙って idle に戻すのではなく、エラーとして見せる"
        )
    }

    /// 「もう一度送信」の手段: エラーを閉じれば、同じ入力のまま即座に再送信できる
    /// （新しいボタン部品は作らず、既存の送信ボタンで再送信できることを保証する）。
    func test_afterTurnstileFailureDismissed_canSubmitAgainImmediately() {
        let vm = makeAwaitingViewModel()
        vm.failTurnstile(.turnstileVerificationFailed)
        vm.dismissError()

        XCTAssertEqual(vm.state, .idle)
        XCTAssertTrue(vm.canSubmit, "エラーを閉じた後、同じ内容ですぐ『もう一度送信』できる")
    }

    func test_failTurnstile_isNoOp_whenNotAwaitingTurnstile() {
        let vm = ReportFormViewModel(apiClient: NeverCalledClient(), onSuccess: { _ in })
        XCTAssertEqual(vm.state, .idle)

        vm.failTurnstile(.turnstileVerificationFailed)

        XCTAssertEqual(vm.state, .idle, "確認待ち以外からの呼び出しでは何もしない")
    }

    /// A-88 修正②: 送信中（`.submitting`）に `failTurnstile` が呼ばれても状態は変わらない
    /// （guard が `.awaitingTurnstile` 以外を弾くことの確認。`HangingClient` で
    /// `.submitting` のまま止めて確かめる）。
    func test_failTurnstile_isNoOp_whileSubmitting() async {
        let vm = ReportFormViewModel(apiClient: HangingClient(), onSuccess: { _ in })
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        vm.selectedSeenIn = .safari
        vm.beginSubmit()

        let task = Task { await vm.completeSubmit(turnstileResponse: "tt_dummy") }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(vm.state, .submitting, "前提: completeSubmit は先に .submitting へ遷移する")

        vm.failTurnstile(.turnstileVerificationFailed)
        XCTAssertEqual(vm.state, .submitting, "確認待ち以外からの呼び出しでは何もしない（送信中は変わらない）")

        task.cancel()
    }

    // MARK: - A-88 修正②: 「もう一度送信」で確認待ちへ戻れること

    /// エラーを閉じてから再度 `beginSubmit()` すれば、同じ入力のまま確認待ちに戻る
    /// （View 側は「アラートの action → 次のランループで beginSubmit」という形で
    /// この 2 手順を呼ぶ。ViewModel 側の契約として固定する）。
    func test_dismissErrorThenBeginSubmit_returnsToAwaitingTurnstile() {
        let vm = makeAwaitingViewModel()
        vm.failTurnstile(.turnstileVerificationFailed)
        vm.dismissError()

        vm.beginSubmit()

        XCTAssertEqual(vm.state, .awaitingTurnstile, "『もう一度送信』は確認待ちへ戻ってやり直せる")
    }

    // MARK: - A-88 修正②の保険: ウォッチドッグ

    /// シートが一度も解決しないまま固まった場合、注入したタイムアウト後に
    /// 自動でエラーへ戻る（本番の既定値は 35 秒だが、テストでは短い値を注入する）。
    func test_awaitingTurnstileWatchdog_firesAfterTimeout_whenNeverResolved() async {
        let vm = ReportFormViewModel(
            apiClient: NeverCalledClient(),
            awaitingTurnstileTimeout: .milliseconds(30),
            onSuccess: { _ in }
        )
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        XCTAssertEqual(vm.state, .awaitingTurnstile)

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(
            vm.state, .error(.turnstileVerificationFailed),
            "確認待ちのまま固まったら保険のタイマーで自動的にエラーへ戻す"
        )
    }

    /// 送信が正常に完了していれば、ウォッチドッグは後から発火しても状態を壊さない
    /// （`completeSubmit` の先頭でキャンセルされているはず）。
    func test_awaitingTurnstileWatchdog_doesNotFireAfterSuccessfulCompletion() async {
        let vm = ReportFormViewModel(
            apiClient: SucceedingClient(),
            awaitingTurnstileTimeout: .milliseconds(30),
            onSuccess: { _ in }
        )
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")
        XCTAssertEqual(vm.state, .idle)

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(vm.state, .idle, "送信完了後は保険のタイマーが状態を壊さない")
    }

    /// キャンセル（シートを閉じた）でもウォッチドッグは止まる。
    func test_awaitingTurnstileWatchdog_doesNotFireAfterCancel() async {
        let vm = ReportFormViewModel(
            apiClient: NeverCalledClient(),
            awaitingTurnstileTimeout: .milliseconds(30),
            onSuccess: { _ in }
        )
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        vm.cancelTurnstile()
        XCTAssertEqual(vm.state, .idle)

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(vm.state, .idle, "キャンセル後は保険のタイマーが状態を壊さない")
    }

    // MARK: - A-88 修正③: 連続失敗のカウント

    func test_turnstileFailureCount_incrementsOnEachFailure_andResetsAfterSuccess() async {
        let client = SucceedingClient()
        let vm = ReportFormViewModel(apiClient: client, onSuccess: { _ in })
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        vm.selectedSeenIn = .safari

        vm.beginSubmit()
        vm.failTurnstile(.turnstileVerificationFailed)
        XCTAssertEqual(vm.turnstileFailureCount, 1)
        XCTAssertFalse(vm.hasRepeatedTurnstileFailure, "1 回目はまだ再送信を促す")

        vm.dismissError()
        vm.beginSubmit()
        vm.failTurnstile(.turnstileVerificationFailed)
        XCTAssertEqual(vm.turnstileFailureCount, 2)
        XCTAssertTrue(vm.hasRepeatedTurnstileFailure, "2 回続けて失敗したらお問い合わせを案内する")

        vm.dismissError()
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertEqual(vm.turnstileFailureCount, 0, "送信成功で回数をリセットする")
        XCTAssertFalse(vm.hasRepeatedTurnstileFailure)
    }
}
