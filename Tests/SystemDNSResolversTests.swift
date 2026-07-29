import XCTest
@testable import AdblockKeshi

/// SystemDNSResolvers.parse（/etc/resolv.conf テキスト → nameserver アドレス抽出）のテスト。
/// 4.0.1 hotfix: モバイル回線(NAT64/DNS64)対応 — トンネル確立前にキャリア DNS を snapshot するための純関数。
final class SystemDNSResolversTests: XCTestCase {

    func test_parse_singleV4Nameserver() {
        let text = "nameserver 192.168.1.1\n"
        XCTAssertEqual(SystemDNSResolvers.parse(resolvConfText: text), ["192.168.1.1"])
    }

    func test_parse_multipleServers_preservesOrder() {
        let text = """
        nameserver 2001:db8::1
        nameserver 192.168.1.1
        """
        XCTAssertEqual(SystemDNSResolvers.parse(resolvConfText: text),
                       ["2001:db8::1", "192.168.1.1"])
    }

    func test_parse_ignoresCommentsAndOtherKeywords() {
        let text = """
        # comment line
        ; another comment
        domain example.co.jp
        search example.co.jp
        options timeout:1
        nameserver 10.0.0.1
        """
        XCTAssertEqual(SystemDNSResolvers.parse(resolvConfText: text), ["10.0.0.1"])
    }

    func test_parse_toleratesLeadingWhitespaceAndTabs() {
        let text = "  \tnameserver\t10.0.0.53  \n"
        XCTAssertEqual(SystemDNSResolvers.parse(resolvConfText: text), ["10.0.0.53"])
    }

    func test_parse_keepsScopedIPv6() {
        // Wi-Fi ルータがリンクローカル DNS を配る構成（fe80::1%en0）は scope 付きのまま保持する
        let text = "nameserver fe80::1%en0\n"
        XCTAssertEqual(SystemDNSResolvers.parse(resolvConfText: text), ["fe80::1%en0"])
    }

    func test_parse_nameserverWithoutAddress_isSkipped() {
        let text = "nameserver\nnameserver 10.0.0.1\n"
        XCTAssertEqual(SystemDNSResolvers.parse(resolvConfText: text), ["10.0.0.1"])
    }

    func test_parse_emptyText_returnsEmpty() {
        XCTAssertEqual(SystemDNSResolvers.parse(resolvConfText: ""), [])
    }
}
