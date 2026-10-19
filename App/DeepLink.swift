import Foundation

/// アプリ内イベント（ASC）などから届くディープリンクをタブへ解決する。
/// 受け付ける形は `adblockkeshi://<タブ名>`（C-88・2026-09-23）。
/// 未知の URL は nil（現在の画面のまま何もしない）に倒す。
/// タブの中に押し込む画面。道（path）で持つので、リンクが届いた時に根元まで戻せる（D-150）。
enum PushedScreen: Hashable {
    /// アプリ内広告ブロック（購入画面または有効化の画面）
    case dns
    /// ブロックを止めているサイトの一覧
    case exceptions
    /// このアプリについて
    case about
}

enum DeepLink {
    static let scheme = "adblockkeshi"

    /// リンク到着の通知。開いている購入画面（`ProPaywallSheet`）が受けて自分を閉じる。
    /// ルートの処理は設定タブが持つシートまで届かず、タブ切替が購入画面の下で起きて行き先が見えないため。
    /// 行き先が分かったリンクだけで出す（未対応の URL では何も閉じない・D-150 決まり 1）。
    /// userInfo に行き先のタブを載せる＝押し込みを持つタブが「自分宛てか」を見分けて根元まで戻る。
    static let didArrive = Notification.Name("AdblockKeshi.DeepLink.didArrive")
    private static let tabKey = "tab"

    static func announceArrival(at tab: AppTab) {
        NotificationCenter.default.post(name: didArrive, object: nil, userInfo: [tabKey: tab])
    }

    static func destinationTab(of notification: Notification) -> AppTab? {
        notification.userInfo?[tabKey] as? AppTab
    }

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
