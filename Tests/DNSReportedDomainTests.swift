import XCTest
@testable import AdblockKeshi

/// DNSReportedDomain.extract（報告URL→DNSドメイン抽出）のテスト。
final class DNSReportedDomainTests: XCTestCase {

    func test_extract_returnsLowercasedHost() {
        XCTAssertEqual(
            DNSReportedDomain.extract(fromURLString: "https://Ads.Example.com/banner?x=1"),
            "ads.example.com")
    }

    func test_extract_stripsPathAndQuery() {
        XCTAssertEqual(
            DNSReportedDomain.extract(fromURLString: "http://track.adnet.jp/pixel/123?u=abc"),
            "track.adnet.jp")
    }

    func test_extract_nil_forCriticalDomain() {
        // critical（DNSCriticalGuard）は自己リストに入れない
        XCTAssertNil(DNSReportedDomain.extract(fromURLString: "https://push.apple.com/x"))
        XCTAssertNil(DNSReportedDomain.extract(fromURLString: "https://kureho.github.io/self"))
    }

    func test_extract_nil_whenNoHost() {
        XCTAssertNil(DNSReportedDomain.extract(fromURLString: "not a url"))
        XCTAssertNil(DNSReportedDomain.extract(fromURLString: ""))
    }
}
