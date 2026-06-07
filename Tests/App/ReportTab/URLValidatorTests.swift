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

    func testTooLong_isRejected() {
        let long = "https://example.com/" + String(repeating: "a", count: 200)
        XCTAssertEqual(URLValidator.validate(long), .invalid(.tooLong))
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
