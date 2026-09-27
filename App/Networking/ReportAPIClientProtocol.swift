import Foundation

/// A-88 §3: `POST /v1/reports/status` の 1 件分の結果。url/memo/uuid_hash 等は返らない
/// （サーバーは大まかな結果だけを返す設計＝設計 `tasks/a88-design-2026-09-27.md` §3）。
struct ReportOutcomeResult: Equatable, Sendable {
    /// サーバー側の報告 ID（`ReportHistoryItem.serverId` と対応）。
    let id: String
    /// `checking/applied/in_app_ad/site_own_ad/declined` のいずれか（丸め後の値）。
    let outcome: String
}

/// Protocol for report API client. Chunk 4 で本実装、Chunk 3 では Mock で test.
protocol ReportAPIClientProtocol: Sendable {
    /// - Parameters:
    ///   - url: 問題が起きた **閲覧ページ** の URL（広告の配信元ではない）。
    ///   - reportKind: 報告種別（広告が消えない / サイトが壊れた）。v4.2.0 クライアントは必ず送る。
    ///   - seenIn: どこで見たか。D-lite クライアントは必ず送る（サーバはこの有無で新旧を判定する）。
    ///   - diagnostics: 自動取得した診断情報。全項目 nullable で、取れていなくても送信は成立する。
    /// - Returns: サーバーが発行した報告 ID（A-88 §1・履歴保存 → 週次判定結果の問い合わせに使う）。
    ///   エラー系テスト等、id が要らない呼び出しで捨てても警告が出ないよう discardable にする。
    @discardableResult
    func submitReport(url: URL, memo: String?, adType: AdType?, reportKind: ReportKind,
                      seenIn: SeenIn, diagnostics: ReportDiagnostics) async throws -> String
    /// Mint an HMAC token bound to `scope` by handing the Workers a fresh
    /// Turnstile response. Cached in HMACTokenStore so subsequent
    /// `submitReport` calls within ~5 minutes do not need a new challenge.
    func requestToken(turnstileResponse: String, scope: TokenScope) async throws
    /// A-88 §3: 報告 ID から週次判定の結果を取りに行く。1 回 20 件まで（呼び出し側の責務・
    /// `LocalReportHistoryStore.refreshStatuses` が chunk する）。存在しない ID は結果から単純に外れる。
    /// 失敗は例外を投げる（ロボット確認は不要な認可なしエンドポイントのため、通信エラーのみ想定）。
    func fetchReportOutcomes(ids: [String]) async throws -> [ReportOutcomeResult]
}
