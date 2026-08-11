import Foundation

/// 報告フォームの「どこで広告を見ましたか？」。
///
/// サーバ (`workers/src/lib/seen-in.ts` の `SEEN_IN_VALUES`) と **完全同期**させる。
/// rawValue がずれると submit が値を認識できず、報告が `observation_legacy`
/// （旧クライアント扱い）に落ちて自動改善の母集団から外れる。
///
/// D-lite の中核: Safari 用 Content Blocker で対処できる報告かどうかを切り分ける。
/// `otherApp`（アプリ内広告）は Safari 用フィルタでは原理的に消せないため、
/// 自動改善パイプラインには乗せず、診断データとしてのみ使う。
enum SeenIn: String, CaseIterable, Identifiable, Sendable {
    case safari
    case otherApp = "other_app"

    var id: String { rawValue }

    /// 選択肢の見出し。
    var title: String {
        switch self {
        case .safari:   return "Safari"
        case .otherApp: return "Safari 以外のアプリ"
        }
    }

    /// 選択肢の補足（どちらか迷わせないための具体例）。
    var detail: String {
        switch self {
        case .safari:   return "Safari でウェブページを見ているときに出た"
        case .otherApp: return "ゲーム・SNS・動画アプリなど、アプリの中で出た"
        }
    }

    var iconSystemName: String {
        switch self {
        case .safari:   return "safari"
        case .otherApp: return "apps.iphone"
        }
    }

    /// Safari 用 Content Blocker の守備範囲かどうか。
    /// `false` の報告は「フィルタを足せば消える」種類のものではないので、
    /// 送信後にその旨を伝える（黙ると「報告したのに消えない」不満に戻る）。
    var isCoveredByContentBlocker: Bool {
        switch self {
        case .safari:   return true
        case .otherApp: return false
        }
    }
}
