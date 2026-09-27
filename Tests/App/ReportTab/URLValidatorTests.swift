import XCTest
@testable import AdblockKeshi

final class URLValidatorTests: XCTestCase {
    func testValidURL_https_passes() {
        XCTAssertEqual(URLValidator.validate("https://example.com"), .valid(URL(string: "https://example.com")!))
    }

    func testValidURL_withPathAndQuery_passes() {
        if case .valid(let url) = URLValidator.validate("https://example.com/article/123?q=test") {
            XCTAssertEqual(url.host, "example.com")
        } else { XCTFail("Expected valid") }
    }

    func testHTTP_isRejected() {
        XCTAssertEqual(URLValidator.validate("http://example.com"), .invalid(.httpNotAllowed))
    }

    func testEmpty_isRejected() {
        XCTAssertEqual(URLValidator.validate(""), .invalid(.empty))
    }

    func testWhitespaceOnly_isRejected() {
        XCTAssertEqual(URLValidator.validate("   "), .invalid(.empty))
    }

    /// A-88 修正①: 上限は 2048（送信形 `absoluteString` の長さ）。ASCII のみなら
    /// percent-encoding で伸びないので raw と送信形は一致する。
    func testTooLong_atBoundary2048_isValid() {
        let prefix = "https://example.com/"
        let raw = prefix + String(repeating: "a", count: URLValidator.maxLength - prefix.count)
        guard case .valid(let url) = URLValidator.validate(raw) else {
            return XCTFail("2048 文字ちょうど（送信形）は許可する")
        }
        XCTAssertEqual(url.absoluteString.count, URLValidator.maxLength)
    }

    func testTooLong_over2048_isRejected() {
        let prefix = "https://example.com/"
        let raw = prefix + String(repeating: "a", count: URLValidator.maxLength - prefix.count + 1)
        XCTAssertEqual(URLValidator.validate(raw), .invalid(.tooLong))
    }

    /// A-88 修正①の本丸: 日本語等は percent-encoding で送信形が生文字列より大きく膨らむ。
    /// 実測で生73字・送信形233字の URL が旧実装（生文字列を200文字で判定）では
    /// サーバ側の url_too_long（当時の上限200）に弾かれ、自動停止の原因になっていた。
    /// 実測の内訳: ASCII 53字（不変）+ 日本語 20字（1字→9字に percent-encoding）
    /// = 生 53+20=73字、送信形 53+20*9=233字。
    func testJapaneseURL_isJudgedBySentForm_notRawInput() {
        let jp = String(repeating: "あ", count: 20)
        let asciiSuffix = String(repeating: "a", count: 33)
        let raw = "https://example.com/" + jp + asciiSuffix
        XCTAssertEqual(raw.count, 73, "前提: 生文字列は73字")

        guard case .valid(let url) = URLValidator.validate(raw) else {
            return XCTFail("日本語入り URL（生73字・送信形233字）は 2048 以内なので通るはず")
        }
        XCTAssertEqual(url.absoluteString.count, 233, "前提: 送信形は233字（percent-encodingで膨張）")
    }

    func testNoScheme_isRejected() {
        XCTAssertEqual(URLValidator.validate("example.com"), .invalid(.malformed))
    }

    func testEmptyHost_isRejected() {
        XCTAssertEqual(URLValidator.validate("https://"), .invalid(.malformed))
    }

    func testShortDomain_isRejected() {
        XCTAssertEqual(URLValidator.validate("https://a.io"), .invalid(.suspiciouslyShort))
    }

    func testTrailingSpace_trimmedAndAccepted() {
        if case .valid(let url) = URLValidator.validate(" https://example.com  ") {
            XCTAssertEqual(url.absoluteString, "https://example.com")
        } else { XCTFail("Trimmed should pass") }
    }
}

final class MemoValidatorTests: XCTestCase {
    func testEmpty_isValid() {
        XCTAssertEqual(MemoValidator.validate(""), .valid)
    }

    func testTypicalMemo_isValid() {
        XCTAssertEqual(MemoValidator.validate("動画上のオーバーレイ広告"), .valid)
    }

    func testTooLong_isRejected() {
        let long = String(repeating: "a", count: 201)
        XCTAssertEqual(MemoValidator.validate(long), .invalid(.tooLong))
    }

    func testContainsHTTPSURL_isRejected() {
        XCTAssertEqual(MemoValidator.validate("これ https://example.com で表示されてる"),
                       .invalid(.containsURL))
    }

    func testContainsHTTPURL_isRejected() {
        XCTAssertEqual(MemoValidator.validate("http://spam.com を見ろ"),
                       .invalid(.containsURL))
    }

    func testMultiline_5LinesOk() {
        let memo = "1\n2\n3\n4\n5"
        XCTAssertEqual(MemoValidator.validate(memo), .valid)
    }

    func testMultiline_6LinesRejected() {
        let memo = "1\n2\n3\n4\n5\n6"
        XCTAssertEqual(MemoValidator.validate(memo), .invalid(.tooManyLines))
    }
}
