import XCTest
@testable import AdblockKeshi

/// サーバ 400 応答 → APIError マッピングの検証。
///
/// D-lite: 保護ドメイン（yahoo.co.jp / apple.com 等）の拒否は**サーバから廃止**された。
/// 報告は「ブロック対象の指定」ではなく「広告が消えなかったページ」の改善用データなので、
/// これらを送るのは正常な操作。したがって専用のエラー種別も持たない。
final class APIErrorFromBodyTests: XCTestCase {

    private func body(error: String, message: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["error": error, "message": message])
    }

    func test_validationMessage_staysValidationFailed() throws {
        let data = body(error: "validation_failed", message: "url must be https")
        let err = try APIError.fromBody(data: data, statusCode: 400)
        guard case .validationFailed = err else {
            return XCTFail("validation_failed は入力エラーとして扱う: \(err)")
        }
    }

    /// 旧仕様の critical_domain 応答が万一返っても、専用扱いはせず通常の入力エラーにする。
    func test_legacyCriticalDomainMessage_isTreatedAsOrdinaryValidationError() throws {
        let data = body(error: "validation_failed", message: "critical_domain: apple.com is protected")
        let err = try APIError.fromBody(data: data, statusCode: 400)
        guard case .validationFailed = err else {
            return XCTFail("専用エラーは廃止した: \(err)")
        }
    }

    func test_rateLimit_mapsWithRetryAfter() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "error": "rate_limit_exceeded", "message": "uuid_daily_limit", "retry_after": 86400,
        ])
        let err = try APIError.fromBody(data: data, statusCode: 429)
        guard case .rateLimitExceeded(let after) = err else {
            return XCTFail("rate limit にマップされること: \(err)")
        }
        XCTAssertEqual(after, 86400)
    }
}
