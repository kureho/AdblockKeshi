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
}
