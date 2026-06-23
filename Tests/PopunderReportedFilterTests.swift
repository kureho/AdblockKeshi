import XCTest
@testable import AdblockKeshi

/// 報告反映へ reported を統合する際の L2 許可ドメイン除外フィルタ（プレーヤー破壊防止）。
final class PopunderReportedFilterTests: XCTestCase {

    private func ipr(_ host: String, ifDomain: String) -> ContentBlockerRule {
        let esc = host.replacingOccurrences(of: ".", with: #"\."#)
        return ContentBlockerRule(
            trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?"# + esc + "[/:]", ifDomain: [ifDomain]),
            action: .init(type: "ignore-previous-rules"))
    }
    private func broadBlock(ifDomain: String) -> ContentBlockerRule {
        ContentBlockerRule(trigger: .init(urlFilter: ".*", ifDomain: [ifDomain],
                                          resourceType: ["script"], loadType: ["third-party"]),
                           action: .init(type: "block"))
    }

    func test_host_extraction_from_url_filter() {
        XCTAssertEqual(PopunderReportedFilter.host(fromURLFilter: #"^[^:]+://+([^:/]+\.)?gstatic\.com[/:]"#), "gstatic.com")
        XCTAssertEqual(PopunderReportedFilter.host(fromURLFilter: #"^[^:]+://+([^:/]+\.)?tokyo-motion\.net[/:]"#), "tokyo-motion.net")
        XCTAssertNil(PopunderReportedFilter.host(fromURLFilter: ".*")) // 広域 block は host 無し
    }

    func test_l2_allowed_domains_extracted_from_ipr_rules() {
        let popunder = [
            broadBlock(ifDomain: "*tokyomotion.net"),
            ipr("fluidplayer.com", ifDomain: "*tokyomotion.net"),
            ipr("googleapis.com", ifDomain: "*tokyomotion.net"),
            ipr("gstatic.com", ifDomain: "*tokyomotion.net"),
            broadBlock(ifDomain: "*streamtape.com"),
            ipr("gstatic.com", ifDomain: "*streamtape.com"),
            ipr("google.com", ifDomain: "*streamtape.com"),
            // L1 host block（ipr ではないので allow 対象外）
            ContentBlockerRule(trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?popads\.net[/:]"#,
                                              resourceType: ["script"]), action: .init(type: "block")),
        ]
        let allowed = PopunderReportedFilter.l2AllowedDomains(popunderRules: popunder)
        XCTAssertEqual(allowed, ["fluidplayer.com", "googleapis.com", "gstatic.com", "google.com"])
        XCTAssertFalse(allowed.contains("popads.net")) // L1 block は許可ドメインでない
    }

    // reported ルールを host-block 形式で直接構築（CriticalDomainGuard 非依存でフィルタ単体を検証）。
    private func reportedBlock(_ host: String) -> ContentBlockerRule {
        let esc = host.replacingOccurrences(of: ".", with: #"\."#)
        return ContentBlockerRule(
            trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?"# + esc + "[/:]",
                           resourceType: ["image", "script"], loadType: ["third-party"]),
            action: .init(type: "block"))
    }

    func test_excludes_reported_matching_l2_allowed_domain_and_subdomain() {
        let allowed: Set<String> = ["gstatic.com", "google.com"]
        let adRule = reportedBlock("ads.test")
        let gstaticRule = reportedBlock("gstatic.com")
        let subRule = reportedBlock("ssl.gstatic.com")
        let out = PopunderReportedFilter.excludingL2Allowed([adRule, gstaticRule, subRule], allowed: allowed)
        XCTAssertTrue(out.contains(adRule), "無関係な広告 reported は残る")
        XCTAssertFalse(out.contains(gstaticRule), "L2 許可ドメインそのものの reported は除外")
        XCTAssertFalse(out.contains(subRule), "L2 許可ドメインのサブドメインの reported も除外")
        XCTAssertEqual(out, [adRule])
    }

    func test_no_exclusion_when_no_allowed() {
        let adRule = reportedBlock("ads.test")
        XCTAssertEqual(PopunderReportedFilter.excludingL2Allowed([adRule], allowed: []), [adRule])
    }
}
