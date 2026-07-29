import Foundation

/// システム DNS リゾルバの snapshot（4.0.1 hotfix: モバイル回線 NAT64/DNS64 対応）。
/// トンネル確立「前」に /etc/resolv.conf を読むことで、その回線が本来使う DNS（キャリア DNS64 含む）を得る。
/// 確立後は resolv.conf が sentinel に置き換わるため、読むタイミングが本質（UpstreamPlanner 側で sentinel 除外の防御もある）。
enum SystemDNSResolvers {

    /// resolv.conf テキストから nameserver アドレスを出現順に抽出する（純関数）。
    static func parse(resolvConfText: String) -> [String] {
        resolvConfText.split(separator: "\n").compactMap { line in
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count >= 2, tokens[0] == "nameserver" else { return nil }
            return String(tokens[1])
        }
    }

    /// 実機 I/O: /etc/resolv.conf を読んで parse する。読めなければ空（→ planner が fallback を使う）。
    static func snapshot() -> [String] {
        guard let text = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) else { return [] }
        return parse(resolvConfText: text)
    }
}
