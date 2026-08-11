import Foundation
import SwiftUI

enum ReportFormState: Equatable {
    case idle
    case awaitingTurnstile
    case submitting
    case error(APIError)
}

@MainActor
final class ReportFormViewModel: ObservableObject {
    /// 広告が消えなかった **閲覧ページ** の URL（広告の配信元ではない）。
    @Published var urlInput: String = ""
    @Published var memoInput: String = ""
    /// ユーザーが選択した広告タイプ。nil = 未選択 (送信不可)。
    @Published var selectedAdType: AdType?
    /// どこで広告を見たか。nil = 未選択 (送信不可)。サーバの `seen_in` と同期。
    @Published var selectedSeenIn: SeenIn?
    @Published private(set) var state: ReportFormState = .idle

    private let apiClient: ReportAPIClientProtocol
    private let historyStore: LocalReportHistoryStore?
    private let onSuccess: (SeenIn) -> Void
    /// 診断情報の自動取得。nil なら添付なしで送る（テスト既定）。
    private let diagnosticsCollector: ReportDiagnosticsCollecting?

    init(apiClient: ReportAPIClientProtocol,
         historyStore: LocalReportHistoryStore? = nil,
         diagnosticsCollector: ReportDiagnosticsCollecting? = nil,
         onSuccess: @escaping (SeenIn) -> Void) {
        self.apiClient = apiClient
        self.historyStore = historyStore
        self.diagnosticsCollector = diagnosticsCollector
        self.onSuccess = onSuccess
    }

    var validatedURL: URL? {
        if case .valid(let url) = URLValidator.validate(urlInput) { return url }
        return nil
    }

    /// D-lite: 保護ドメイン（yahoo.co.jp / apple.com 等）の送信前ガードは撤去した。
    /// 報告は「ブロック対象の指定」ではなく「広告が消えなかったページ」の改善用データなので、
    /// 大手サイトを報告するのは**正常な操作**。サーバも受理する。
    /// 自動でブロックルールへ昇格させないのはサーバ側 safety gate（L3）の責務。
    var urlError: String? {
        guard !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if case .invalid(let reason) = URLValidator.validate(urlInput) {
            return reason.userMessage
        }
        return nil
    }

    var memoError: String? {
        guard !memoInput.isEmpty else { return nil }
        if case .invalid(let reason) = MemoValidator.validate(memoInput) {
            return reason.userMessage
        }
        return nil
    }

    var canSubmit: Bool {
        guard validatedURL != nil else { return false }
        guard selectedAdType != nil else { return false }
        guard selectedSeenIn != nil else { return false }
        if !memoInput.isEmpty, case .invalid = MemoValidator.validate(memoInput) { return false }
        if case .submitting = state { return false }
        if case .awaitingTurnstile = state { return false }
        return true
    }

    var showsTurnstileSheet: Bool {
        if case .awaitingTurnstile = state { return true }
        return false
    }

    var memoCharCount: Int { memoInput.count }
    var memoCharRemaining: Int { MemoValidator.maxLength - memoInput.count }

    /// User tapped 送信. We don't hit the API yet — we need a fresh Turnstile
    /// token first. The view binds `showsTurnstileSheet` to drive presentation.
    func beginSubmit() {
        guard canSubmit, validatedURL != nil else { return }
        state = .awaitingTurnstile
    }

    /// Cancelled out of the Turnstile sheet without completing.
    func cancelTurnstile() {
        if case .awaitingTurnstile = state { state = .idle }
    }

    /// Turnstile widget produced a response token. Exchange it for an HMAC
    /// token, then send the report.
    func completeSubmit(turnstileResponse: String) async {
        guard let url = validatedURL, let seenIn = selectedSeenIn else { state = .idle; return }
        state = .submitting
        do {
            try await apiClient.requestToken(turnstileResponse: turnstileResponse, scope: .submit)
            let memo = memoInput.isEmpty ? nil : memoInput
            // 診断情報は best-effort。取れなくても（collector 未注入でも）送信は続行する。
            // 失敗はユーザーへ一切見せない（診断が取れないから報告できない、は本末転倒）。
            let diagnostics = await diagnosticsCollector?.collect() ?? .unavailable
            try await apiClient.submitReport(
                url: url, memo: memo, adType: selectedAdType,
                seenIn: seenIn, diagnostics: diagnostics
            )
            // D-lite: 報告は改善用データであり、その端末で即ブロックはしない。
            // したがって履歴は常に「受付済」から始まる。
            historyStore?.append(url: url, memo: memo, status: .pending)
            state = .idle
            urlInput = ""
            memoInput = ""
            selectedAdType = nil
            selectedSeenIn = nil
            onSuccess(seenIn)
            // 発火カウントは日数ベース（AdblockKeshiApp.bumpDailyUsageIfNeeded）に統一したため
            // 報告成功での bump は行わない（2026-06-11 kureho 判断）
        } catch let err as APIError {
            state = .error(err)
            ReviewPrompt.recordNegativeEvent()
        } catch {
            state = .error(.decodingFailed)
            ReviewPrompt.recordNegativeEvent()
        }
    }

    func dismissError() {
        if case .error = state { state = .idle }
    }
}
