import XCTest
@testable import AdblockKeshi

/// 送信失敗時の文言が実態と合っているかの回帰テスト。
/// 点検記録 `tasks/report-pipeline-audit-2026-09-27.md` ③ の 4 件のうち、
/// `APIError.errorDescription` の文言そのものに関わる項目を固定する。
///
/// A-88 修正⑥: 「含まない」だけの緩いアサーションは文言が実態とズレても検知できない
/// ため、期待文言との完全一致 (`XCTAssertEqual`) にする。
final class APIErrorMessageTests: XCTestCase {

    // MARK: - 2) 送信停止中（403 banned）

    /// サーバは実際の停止期間（24h/7d/30d/permanent）を返さないため期限は断定しない。
    /// 無期限の停止もあり、かつ停止中に送り直すと停止が延びる作りだった（サーバ側は別途
    /// 修正）ため、「一時的に」「しばらく経ってから」とは言わない。
    /// 「アプリを再起動してください」（= unauthorized の文言。再起動しても直らない）も出さない。
    func test_banned_message_isExactWording() {
        let message = APIError.banned(level: 1, expiresAt: Date()).errorDescription
        XCTAssertEqual(message, "現在この端末からの報告を停止しています。心当たりがない場合はお問い合わせください")
    }

    // MARK: - 3) 送信間隔・日次・月次の上限

    /// サーバが返す retryAfter は 日次 86400 / 月次 2,592,000 / IP 15分 900 の
    /// 3 通り (`workers/src/handlers/submit.ts:124-126`)。ここでは日次を固定する。
    func test_dailyLimit_message_isExactWording() {
        let message = APIError.rateLimitExceeded(retryAfter: 86400).errorDescription
        XCTAssertEqual(message, "1 日の上限に達しました。明日また送信できます")
    }

    /// 月次上限（30日 = 2,592,000 秒）で「明日また送信できます」と言うと嘘になる。
    func test_monthlyLimit_message_isExactWording() {
        let message = APIError.rateLimitExceeded(retryAfter: 30 * 86400).errorDescription
        XCTAssertEqual(message, "月の送信上限に達しました。しばらく経ってから送信できます")
    }

    /// IP の 15 分制限 (900 秒 = 0時間) は「送信間隔が短すぎます」側に入る。
    func test_ip15MinLimit_message_isExactWording() {
        let message = APIError.rateLimitExceeded(retryAfter: 900).errorDescription
        XCTAssertEqual(message, "送信間隔が短すぎます。少し時間を空けてください")
    }

    // MARK: - 4) 入力の不備（サーバー判定）

    /// サーバの生文言（英語混じり・技術用語）をそのまま画面に出さない。field は常に
    /// "url" 固定でしか来ないため、URL・メモ両方に触れる汎用文言に完全一致させる。
    func test_validationFailed_message_isExactWording() {
        let message = APIError.validationFailed(field: "url", reason: "url must be https").errorDescription
        XCTAssertEqual(message, "入力内容をご確認ください（URL の形式やメモの長さなど）")
    }

    func test_validationFailed_message_isExactWording_memoCase() {
        let message = APIError.validationFailed(field: "memo", reason: "memo exceeds 500 chars").errorDescription
        XCTAssertEqual(message, "入力内容をご確認ください（URL の形式やメモの長さなど）")
    }
}
