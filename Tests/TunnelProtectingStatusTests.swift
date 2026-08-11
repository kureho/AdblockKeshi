import XCTest
import NetworkExtension
@testable import AdblockKeshi

/// 報告に添える `dns_enabled` は **購入状態ではなく、実際に保護が動いていたか**。
/// Pro を買っていても tunnel が止まっていれば false でなければ診断価値がない。
final class TunnelProtectingStatusTests: XCTestCase {

    func test_connected_isProtecting() {
        XCTAssertTrue(TunnelManager.isProtecting(.connected))
    }

    /// ネットワーク切替中でも tunnel 自体は上がっていて DNS を処理している。
    func test_reasserting_isProtecting() {
        XCTAssertTrue(TunnelManager.isProtecting(.reasserting))
    }

    /// `.connecting` はまだ保護が始まっていない。
    func test_connecting_isNotProtecting() {
        XCTAssertFalse(TunnelManager.isProtecting(.connecting))
    }

    func test_inactiveStatuses_areNotProtecting() {
        for status in [NEVPNStatus.disconnected, .disconnecting, .invalid] {
            XCTAssertFalse(TunnelManager.isProtecting(status), "\(status) は保護中ではない")
        }
    }
}
