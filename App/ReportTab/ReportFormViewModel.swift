import Foundation
import SwiftUI

enum ReportFormState: Equatable {
    case idle
    case submitting
    case error(APIError)
}

@MainActor
final class ReportFormViewModel: ObservableObject {
    @Published var urlInput: String = ""
    @Published var memoInput: String = ""
    @Published private(set) var state: ReportFormState = .idle

    private let apiClient: ReportAPIClientProtocol
    private let onSuccess: () -> Void

    init(apiClient: ReportAPIClientProtocol, onSuccess: @escaping () -> Void) {
        self.apiClient = apiClient
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
        if !memoInput.isEmpty, case .invalid = MemoValidator.validate(memoInput) { return false }
        if case .submitting = state { return false }
        return true
    }

    var memoCharCount: Int { memoInput.count }
    var memoCharRemaining: Int { MemoValidator.maxLength - memoInput.count }

    func submit() async {
        guard canSubmit, let url = validatedURL else { return }
        state = .submitting
        do {
            let memo = memoInput.isEmpty ? nil : memoInput
            try await apiClient.submitReport(url: url, memo: memo)
            state = .idle
            urlInput = ""
            memoInput = ""
            onSuccess()
        } catch let err as APIError {
            state = .error(err)
        } catch {
            state = .error(.decodingFailed)
        }
    }

    func dismissError() {
        if case .error = state { state = .idle }
    }
}
