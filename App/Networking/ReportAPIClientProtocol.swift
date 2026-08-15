import Foundation

/// Protocol for report API client. Chunk 4 で本実装、Chunk 3 では Mock で test.
protocol ReportAPIClientProtocol: Sendable {
    /// - Parameters:
    ///   - url: 問題が起きた **閲覧ページ** の URL（広告の配信元ではない）。
    ///   - reportKind: 報告種別（広告が消えない / サイトが壊れた）。v4.2.0 クライアントは必ず送る。
    ///   - seenIn: どこで見たか。D-lite クライアントは必ず送る（サーバはこの有無で新旧を判定する）。
    ///   - diagnostics: 自動取得した診断情報。全項目 nullable で、取れていなくても送信は成立する。
    func submitReport(url: URL, memo: String?, adType: AdType?, reportKind: ReportKind,
                      seenIn: SeenIn, diagnostics: ReportDiagnostics) async throws
    /// Mint an HMAC token bound to `scope` by handing the Workers a fresh
    /// Turnstile response. Cached in HMACTokenStore so subsequent
    /// `submitReport` calls within ~5 minutes do not need a new challenge.
    func requestToken(turnstileResponse: String, scope: TokenScope) async throws
}
