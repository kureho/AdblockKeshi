import XCTest
@testable import AdblockKeshi

/// UpstreamPlanner.plan（システム DNS snapshot → 上流候補の順序付きリスト）のテスト。
/// 4.0.1 hotfix: キャリア DNS を最優先で使い、sentinel/loopback を除外し、Cloudflare を最後の砦として後置する。
final class UpstreamPlannerTests: XCTestCase {

    private let sentinels: Set<String> = ["198.18.0.1", "fd00::1", "198.18.0.2", "fd00::2"]
    private let fallbacks = ["1.1.1.1", "2606:4700:4700::1111"]

    func test_systemServersFirst_thenFallbacks() {
        let plan = UpstreamPlanner.plan(systemServers: ["2001:db8::53", "192.168.1.1"],
                                        excluding: sentinels, fallbacks: fallbacks)
        XCTAssertEqual(plan, ["2001:db8::53", "192.168.1.1", "1.1.1.1", "2606:4700:4700::1111"])
    }

    func test_emptySnapshot_returnsFallbacksOnly() {
        let plan = UpstreamPlanner.plan(systemServers: [], excluding: sentinels, fallbacks: fallbacks)
        XCTAssertEqual(plan, fallbacks)
    }

    func test_sentinelAddresses_areExcluded() {
        // トンネル稼働中に snapshot すると自分の sentinel が見える。転送ループ防止のため必ず除外
        let plan = UpstreamPlanner.plan(systemServers: ["198.18.0.1", "fd00::1"],
                                        excluding: sentinels, fallbacks: fallbacks)
        XCTAssertEqual(plan, fallbacks)
    }

    func test_loopbackAddresses_areExcluded() {
        let plan = UpstreamPlanner.plan(systemServers: ["127.0.0.1", "::1", "10.0.0.53"],
                                        excluding: sentinels, fallbacks: fallbacks)
        XCTAssertEqual(plan, ["10.0.0.53", "1.1.1.1", "2606:4700:4700::1111"])
    }

    func test_duplicates_areRemoved_preservingFirstOccurrence() {
        let plan = UpstreamPlanner.plan(systemServers: ["10.0.0.53", "10.0.0.53", "1.1.1.1"],
                                        excluding: sentinels, fallbacks: fallbacks)
        XCTAssertEqual(plan, ["10.0.0.53", "1.1.1.1", "2606:4700:4700::1111"])
    }

    func test_invalidAddressTokens_areExcluded() {
        let plan = UpstreamPlanner.plan(systemServers: ["not-an-ip", "999.1.2.3", "10.0.0.53"],
                                        excluding: sentinels, fallbacks: fallbacks)
        XCTAssertEqual(plan, ["10.0.0.53", "1.1.1.1", "2606:4700:4700::1111"])
    }

    func test_scopedIPv6_isValidAndKept() {
        let plan = UpstreamPlanner.plan(systemServers: ["fe80::1%en0"],
                                        excluding: sentinels, fallbacks: fallbacks)
        XCTAssertEqual(plan, ["fe80::1%en0", "1.1.1.1", "2606:4700:4700::1111"])
    }
}
