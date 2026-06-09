import Foundation

/// 報告フォームでユーザーが選択する広告タイプ。サーバ (`workers/src/lib/
/// ad-type.ts` の `AD_TYPES`) と完全同期。並び順も同一（UI のデフォルト並び
/// = テストで固定）。
enum AdType: String, CaseIterable, Identifiable {
    case interstitial
    case popup
    case autoplayVideo = "autoplay_video"
    case stickyBanner = "sticky_banner"
    case fakeClose = "fake_close"
    case fakeNotification = "fake_notification"
    case phishing
    case redirect
    case preroll
    case misleadingLink = "misleading_link"
    case other

    var id: String { rawValue }

    /// 選択画面 1 行目（見出し）。フォーム画面で選択結果を表示するときも
    /// この短い見出しを使うので、長くしすぎない（10 文字程度）。
    var title: String {
        switch self {
        case .interstitial:      return "全画面広告"
        case .popup:             return "ポップアップ"
        case .autoplayVideo:     return "自動再生される動画"
        case .stickyBanner:      return "貼り付く広告"
        case .fakeClose:         return "偽の「閉じる」ボタン"
        case .fakeNotification:  return "偽の通知・警告"
        case .phishing:          return "詐欺サイト"
        case .redirect:          return "自動転送"
        case .preroll:           return "動画の前の広告"
        case .misleadingLink:    return "意図しない別タブ"
        case .other:             return "その他"
        }
    }

    /// 選択画面 2 行目（補足）。具体的な現象や例。
    var detail: String {
        switch self {
        case .interstitial:      return "画面いっぱいに広告が出て先に進めない"
        case .popup:             return "小さな広告ウィンドウが重なって出てくる"
        case .autoplayVideo:     return "勝手に動画や音声が再生される"
        case .stickyBanner:      return "スクロールしても下に貼り付いて消えない"
        case .fakeClose:         return "押しても閉じない / 偽の「閉じる」マーク"
        case .fakeNotification:  return "ウイルス警告などに見せかけた広告"
        case .phishing:          return "個人情報やクレジットカードを入力させる"
        case .redirect:          return "ページを開いた瞬間に別サイトへ飛ばされる"
        case .preroll:           return "動画の本編が始まる前に流れる広告"
        case .misleadingLink:    return "広告のない場所を押すと別タブが開いて、広告ブロックの画面が出る"
        case .other:             return "下のメモに状況を書いてください"
        }
    }

    /// 各タイプを直感的に示す SF Symbol。
    var iconSystemName: String {
        switch self {
        case .interstitial:      return "rectangle.inset.filled"
        case .popup:             return "rectangle.on.rectangle"
        case .autoplayVideo:     return "play.rectangle.fill"
        case .stickyBanner:      return "rectangle.bottomhalf.inset.filled"
        case .fakeClose:         return "xmark.circle.fill"
        case .fakeNotification:  return "exclamationmark.triangle.fill"
        case .phishing:          return "lock.trianglebadge.exclamationmark.fill"
        case .redirect:          return "arrowshape.turn.up.right.fill"
        case .preroll:           return "play.tv.fill"
        case .misleadingLink:    return "link.badge.plus"
        case .other:             return "ellipsis.circle"
        }
    }

    /// 後方互換: 旧 `label` 参照。今は title を返す。
    var label: String { title }
}
