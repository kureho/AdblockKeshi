import Foundation

/// 送信完了画面の文言。
///
/// D-lite では報告は **ブロック対象の指定ではなく、広告フィルタ改善の参考データ**。
/// 「報告したのでこの広告がすぐ消える」と誤認させない。
/// 個別対応の約束（必ず対応する / 確認して修正する / N 日以内に反映する）も書かない。
enum ReportSentMessage {

    static let title = "報告を受け付けました"

    static func body(for seenIn: SeenIn) -> String {
        let base = "いただいた情報は、広告フィルタを改善するための参考として使わせていただきます。"
        guard !seenIn.isCoveredByContentBlocker else { return base }
        // Safari 用フィルタでアプリ内広告は原理的に消せない。
        // ここを黙ると「報告したのに消えない」という元の不満に戻る。
        return base + "\n\nなお、アプリの中に表示される広告は、Safari 用のフィルタでは消すことができません。"
    }
}
