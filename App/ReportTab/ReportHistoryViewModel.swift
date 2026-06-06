import Foundation
import SwiftUI

enum ReportHistoryState: Equatable {
    case loading
    case cached(ReportHistoryResponse)
    case loaded(ReportHistoryResponse)
    case empty
    case error(String)
}

@MainActor
final class ReportHistoryViewModel: ObservableObject {
    @Published private(set) var state: ReportHistoryState
    private let apiClient: ReportHistoryFetcher
    private let cache: ReportHistoryCache

    init(apiClient: ReportHistoryFetcher, cache: ReportHistoryCache) {
        self.apiClient = apiClient
        self.cache = cache
        if let cached = cache.load() {
            self.state = .cached(cached)
        } else {
            self.state = .loading
        }
    }

    func refresh() async {
        do {
            let response = try await apiClient.fetchHistory()
            if response.items.isEmpty {
                state = .empty
                cache.clear()
            } else {
                state = .loaded(response)
                cache.save(response)
            }
        } catch {
            if case .cached = state {
                // keep cached
                return
            } else if let cached = cache.load() {
                state = .cached(cached)
            } else {
                state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}

/// Subset of API client used by the history view (avoid leaking submit/delete dependency).
protocol ReportHistoryFetcher: Sendable {
    func fetchHistory() async throws -> ReportHistoryResponse
}

extension StubReportAPIClient: ReportHistoryFetcher {
    func fetchHistory() async throws -> ReportHistoryResponse {
        try await Task.sleep(nanoseconds: 400_000_000)
        return ReportHistoryResponse(items: [], fetchedAt: Date())
    }
}
