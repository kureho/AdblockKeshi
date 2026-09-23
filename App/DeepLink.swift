import Foundation

/// アプリ内イベント（ASC）などから届くディープリンクをタブへ解決する。
/// 受け付ける形は `adblockkeshi://<タブ名>`（C-88・2026-09-23）。
/// 未知の URL は nil（現在の画面のまま何もしない）に倒す。
enum DeepLink {
    static let scheme = "adblockkeshi"

    static func tab(for url: URL) -> AppTab? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        switch url.host?.lowercased() {
        case "home": return .blocker
        case "report": return .report
        case "settings": return .settings
        default: return nil
        }
    }
}
