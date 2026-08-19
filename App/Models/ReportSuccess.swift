import Foundation

/// 報告送信成功の結果。送信完了画面の文言出し分けと
/// 「このサイトで一時オフ」（per-site 例外）の提示に使う。
struct ReportSuccess: Hashable, Sendable {
    let kind: ReportKind
    let seenIn: SeenIn
    /// 報告した URL の host（小文字化済み・取れなければ空文字）。
    let host: String

    /// 「このサイトでブロックを一時オフ」を提示するか。
    /// Safari の壊れ報告のみ: Safari 以外（アプリ内）は Content Blocker の例外では直らない
    /// （そちらは DNS の時限一時停止が対処）。広告報告に出すと意味が逆になる。
    var offersSiteException: Bool {
        kind == .siteBroken && seenIn == .safari && !host.isEmpty
    }
}
