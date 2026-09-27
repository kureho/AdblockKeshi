import XCTest
@testable import AdblockKeshi

/// 送信失敗時の文言が実態と合っているかの回帰テスト。
/// 点検記録 `tasks/report-pipeline-audit-2026-09-27.md` ③ の 4 件のうち、
/// `APIError.errorDescription` の文言そのものに関わる項目を固定する。
final class APIErrorMessageTests: XCTestCase {

    // MARK: - 2) 送信停止中（403 banned）

    /// サーバは実際の停止期間（24h/7d/30d/permanent）を返さないため、期限を断定しない。
    /// 「アプリを再起動してください」（= unauthorized の文言。再起動しても直らない）を出さない。
    func test_banned_doesNotTellUserToRestartApp() {
        let message = APIError.banned(level: 1, expiresAt: Date()).errorDescription ?? ""
        XCTAssertFalse(message.contains("再起動"), "再起動しても直らないので案内しない: \(message)")
    }

    /// 内部の ban level 番号は利用者に意味がない（サーバも実際の level を返していない＝常に仮の値）。
    func test_banned_messageDoesNotExposeInternalLevelNumber() {
        let message = APIError.banned(level: 1, expiresAt: Date()).errorDescription ?? ""
        XCTAssertFalse(message.lowercased().contains("level"), "内部の level 表記を出さない: \(message)")
    }

    // MARK: - 3) 月の上限

    /// サーバの日次上限は 86400 秒 (`workers/src/lib/rate-limit.ts` UUID_DAILY_LIMIT)。
    func test_dailyLimit_saysTomorrow() {
        let message = APIError.rateLimitExceeded(retryAfter: 86400).errorDescription ?? ""
        XCTAssertTrue(message.contains("明日"), "日次上限は『明日』で正しい: \(message)")
    }

    /// サーバの月次上限は 30日=2,592,000 秒 (`workers/src/lib/rate-limit.ts` UUID_MONTHLY_LIMIT)。
    /// 「明日また送信できます」は月次では嘘になる。
    func test_monthlyLimit_doesNotClaimTomorrow() {
        let message = APIError.rateLimitExceeded(retryAfter: 30 * 86400).errorDescription ?? ""
        XCTAssertFalse(message.contains("明日"), "月次上限なのに『明日また送信できる』と言わない: \(message)")
        XCTAssertTrue(message.contains("月"), "月次上限だとわかる文言にする: \(message)")
    }

    // MARK: - 4) 入力の不備（サーバー判定）

    /// サーバの生文言（英語混じり・技術用語）をそのまま画面に出さない。
    func test_validationFailed_hidesRawServerReason() {
        let message = APIError.validationFailed(field: "url", reason: "url must be https").errorDescription ?? ""
        XCTAssertFalse(message.contains("must be"), "サーバの英語文言をそのまま出さない: \(message)")
        XCTAssertFalse(message.contains("("), "フィールド名などの技術情報を括弧で出さない: \(message)")
    }

    func test_validationFailed_hidesRawServerReason_memoCase() {
        let message = APIError.validationFailed(field: "memo", reason: "memo exceeds 500 chars").errorDescription ?? ""
        XCTAssertFalse(message.contains("exceeds"), "サーバの英語文言をそのまま出さない: \(message)")
    }
}
