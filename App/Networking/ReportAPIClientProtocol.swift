import Foundation

/// Protocol for report API client. Chunk 4 で本実装、Chunk 3 では Mock で test.
protocol ReportAPIClientProtocol: Sendable {
    func submitReport(url: URL, memo: String?, adType: AdType?) async throws
    /// Mint an HMAC token bound to `scope` by handing the Workers a fresh
    /// Turnstile response. Cached in HMACTokenStore so subsequent
    /// `submitReport` calls within ~5 minutes do not need a new challenge.
    func requestToken(turnstileResponse: String, scope: TokenScope) async throws
}
