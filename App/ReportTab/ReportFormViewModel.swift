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
    @Published var urlInput: String = ""
    @Published var memoInput: String = ""
    /// ユーザーが選択した広告タイプ。nil = 未選択 (送信不可)。
    @Published var selectedAdType: AdType?
    @Published private(set) var state: ReportFormState = .idle

    private let apiClient: ReportAPIClientProtocol
    private let historyStore: LocalReportHistoryStore?
    private let onSuccess: () -> Void

    init(apiClient: ReportAPIClientProtocol,
         historyStore: LocalReportHistoryStore? = nil,
         onSuccess: @escaping () -> Void) {
        self.apiClient = apiClient
        self.historyStore = historyStore
        self.onSuccess = onSuccess
    }

    var validatedURL: URL? {
        if case .valid(let url) = URLValidator.validate(urlInput) { return url }
        return nil
    }

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
        guard let url = validatedURL else { state = .idle; return }
        state = .submitting
        do {
            try await apiClient.requestToken(turnstileResponse: turnstileResponse, scope: .submit)
            let memo = memoInput.isEmpty ? nil : memoInput
            try await apiClient.submitReport(url: url, memo: memo, adType: selectedAdType)
            historyStore?.append(url: url, memo: memo)
            state = .idle
            urlInput = ""
            memoInput = ""
            selectedAdType = nil
            onSuccess()
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
