import XCTest
import Darwin
import NetworkExtension
@testable import AdblockKeshi

/// ★実機 + トンネル ON 専用の DNS ブロック検証★
/// トンネルが接続されている時だけ実行する（NETunnelProviderManager の status を自己検出）。
/// トンネル未接続の環境（通常の sim/CI）では自動 skip するので回帰を汚さない。
/// 実行: xcodebuild test -destination 'platform=iOS,id=<device>' \
///        -only-testing:AdblockKeshiTests/TunnelDNSVerificationTests
final class TunnelDNSVerificationTests: XCTestCase {

    private func requireTunnelActive() async throws {
        let status: NEVPNStatus?
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            status = managers.first?.connection.status
        } catch {
            throw XCTSkip("NE 利用不可（sim/CI 等）: \(error.localizedDescription)")
        }
        guard status == .connected else {
            throw XCTSkip("トンネル未接続のため skip（status=\(String(describing: status))）")
        }
    }

    /// host を IPv4 解決して返す（解決不能は空配列）。
    private func resolveIPv4(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0 else { return [] }
        defer { freeaddrinfo(result) }
        var addrs: [String] = []
        var ptr = result
        while let node = ptr {
            if node.pointee.ai_family == AF_INET, let sa = node.pointee.ai_addr {
                var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
                addrs.append(String(cString: buf))
            }
            ptr = node.pointee.ai_next
        }
        return addrs
    }

    func test_adDomainBlocked_normalAndCriticalResolve() async throws {
        try await requireTunnelActive()

        // ① 広告ドメイン（curated リストの doubleclick.net）→ 0.0.0.0 でブロック
        let ad = resolveIPv4("doubleclick.net")
        XCTAssertTrue(ad.contains("0.0.0.0") || ad.isEmpty,
                      "広告ドメインはブロックされるべき（実際: \(ad)）")

        // ② 通常ドメイン（example.com）→ 実 IP に解決（forward）
        let normal = resolveIPv4("example.com")
        XCTAssertFalse(normal.isEmpty, "通常ドメインは解決されるべき")
        XCTAssertFalse(normal.contains("0.0.0.0"), "通常ドメインはブロックされない（実際: \(normal)）")

        // ③ critical（apple.com・DNSCriticalGuard 保護）→ 実 IP（リストにあっても絶対に通す）
        let critical = resolveIPv4("apple.com")
        XCTAssertFalse(critical.isEmpty, "critical は必ず解決されるべき")
        XCTAssertFalse(critical.contains("0.0.0.0"), "critical はブロックされてはいけない（実際: \(critical)）")
    }
}
