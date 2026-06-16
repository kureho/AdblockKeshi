import Foundation

/// popunder/タップ乗っ取り対策フィルタ（既知広告網の script-block）の解決設定を一元化する。
/// App Group の `popunder-rules.json`（将来 CDN 更新で配信）を優先し、無ければ bundle 同梱版に
/// フォールバックする。標準フィルタ側 `BlockerListResolver` と同じ App Group → bundle 構造。
enum PopunderRulesResolver {
    /// popunder 対策ルールのファイル名。bundle 同梱・（将来）App Group で同一名に統一。
    static let filename = "popunder-rules.json"

    static func make() -> BlockerListResolver {
        BlockerListResolver(filterFilename: filename)
    }
}
