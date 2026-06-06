import Foundation

/// Protocol for report API client. Chunk 4 で本実装、Chunk 3 では Mock で test.
protocol ReportAPIClientProtocol: Sendable {
    func submitReport(url: URL, memo: String?) async throws
}
