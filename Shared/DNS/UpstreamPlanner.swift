import Foundation

/// DNS 上流候補の順序付きリストを作る純関数（4.0.1 hotfix: モバイル回線 NAT64/DNS64 対応）。
/// キャリア/ルータのシステム DNS を最優先（DNS64 変換を生かす）、Cloudflare は最後の砦。
/// sentinel（自トンネル宛 = 転送ループ）と loopback は必ず除外する。
enum UpstreamPlanner {

    static func plan(systemServers: [String], excluding: Set<String>, fallbacks: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for server in systemServers + fallbacks {
            guard !excluding.contains(server),
                  !isLoopback(server),
                  isPlausibleIPAddress(server),
                  seen.insert(server).inserted else { continue }
            result.append(server)
        }
        return result
    }

    private static func isLoopback(_ address: String) -> Bool {
        address == "::1" || address.hasPrefix("127.")
    }

    /// inet_pton で v4/v6 として解釈できるか（v6 の %scope は除いて判定・保持は呼び出し側の値のまま）。
    private static func isPlausibleIPAddress(_ address: String) -> Bool {
        let bare = address.split(separator: "%").first.map(String.init) ?? address
        var v4 = in_addr()
        if inet_pton(AF_INET, bare, &v4) == 1 { return true }
        var v6 = in6_addr()
        return inet_pton(AF_INET6, bare, &v6) == 1
    }
}
