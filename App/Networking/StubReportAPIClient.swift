import Foundation

/// Chunk 3 用 placeholder。Chunk 4 で本実装の ReportAPIClient (URLSession + Workers) に差し替え。
/// 開発ビルドではすべての submit を 0.6 秒待ってから成功として返す。
final class StubReportAPIClient: ReportAPIClientProtocol {
    func submitReport(url: URL, memo: String?, adType: AdType?) async throws {
        try await Task.sleep(nanoseconds: 600_000_000)
        // 成功扱い。Chunk 4 で Workers /v1/reports/submit を呼ぶ実装に置き換え。
    }

    func requestToken(turnstileResponse: String, scope: TokenScope) async throws {
        try await Task.sleep(nanoseconds: 100_000_000)
        // no-op stub
    }
}
