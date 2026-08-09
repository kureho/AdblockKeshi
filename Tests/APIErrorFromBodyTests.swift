import XCTest
@testable import AdblockKeshi

/// サーバ 400 応答 → APIError マッピングの検証。
/// critical_domain はクライアント側リストとサーバ側リストがずれた場合の
/// フォールバックとして日本語文言に変換する（通常は送信前に弾かれる）。
final class APIErrorFromBodyTests: XCTestCase {

    private func body(error: String, message: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["error": error, "message": message])
    }

    func test_criticalDomainMessage_mapsToJapaneseGuidance() throws {
        let data = body(error: "validation_failed", message: "critical_domain: apple.com is protected")
        let err = try APIError.fromBody(data: data, statusCode: 400)
        let description = err.localizedDescription
        XCTAssertTrue(description.contains("報告の対象外"), "日本語の説明であること: \(description)")
        XCTAssertFalse(description.contains("critical_domain"), "技術用語をユーザーに見せない")
        XCTAssertFalse(description.contains("入力エラー"), "再入力で直る種類のエラーではない")
    }

    func test_otherValidationMessage_staysValidationFailed() throws {
        let data = body(error: "validation_failed", message: "url must be https")
        let err = try APIError.fromBody(data: data, statusCode: 400)
        guard case .validationFailed = err else {
            return XCTFail("critical_domain 以外の validation_failed は従来どおり: \(err)")
        }
    }
}
