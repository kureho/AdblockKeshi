import XCTest
import NetworkExtension
@testable import AdblockKeshi

/// 報告に添える `dns_enabled` は **購入状態ではなく、実際に保護が動いていたか**。
/// Pro を買っていても tunnel が止まっていれば false でなければ診断価値がない。
final class TunnelProtectingStatusTests: XCTestCase {

    func test_connected_isProtecting() {
        XCTAssertTrue(TunnelManager.isProtecting(.connected))
    }

    /// ★`.reasserting` は保護中ではない。
    /// `PacketTunnelProvider.reassertForNetworkChange()` は切替中に
    /// `setTunnelNetworkSettings(nil)` で設定を一旦外し、システム DNS を復元する。
    /// その間の DNS はブロックエンジンを通らないので、true にすると
    /// 「保護 ON なのに広告が出た」の取りこぼしとして誤分類される。
    func test_reasserting_isNotProtecting() {
        XCTAssertFalse(TunnelManager.isProtecting(.reasserting))
    }

    /// `.connecting` はまだ保護が始まっていない。
    func test_connecting_isNotProtecting() {
        XCTAssertFalse(TunnelManager.isProtecting(.connecting))
    }

    /// 診断の `isProtecting` と 4.0.3 hotfix の reload 対象は**別の問い**。
    /// reload 対象は「extension がメモリ上に DNSEngine を持っているか」なので
    /// `.connecting` / `.reasserting` を含む。ここを揃えてはいけない。
    func test_protectingIsNarrowerThanReloadTarget() {
        XCTAssertFalse(TunnelManager.isProtecting(.connecting))
        XCTAssertFalse(TunnelManager.isProtecting(.reasserting))
        XCTAssertTrue(TunnelManager.isProtecting(.connected))
    }

    func test_inactiveStatuses_areNotProtecting() {
        for status in [NEVPNStatus.disconnected, .disconnecting, .invalid] {
            XCTAssertFalse(TunnelManager.isProtecting(status), "\(status) は保護中ではない")
        }
    }
}
