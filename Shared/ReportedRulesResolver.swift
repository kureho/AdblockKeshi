import Foundation

/// 報告から反映された「学習フィルタ」の解決設定を一元化する。
///
/// FilterDownloader が CDN から保存した App Group の `rules-reported.json` を優先し、
/// 無ければ bundle 同梱の空配列にフォールバックする。標準フィルタ側 `BlockerListResolver`
/// と同じ App Group → bundle の構造を、報告フィルタ用のファイル名で再利用する。
enum ReportedRulesResolver {
    /// 報告フィルタのファイル名。CDN(`docs/cdn/`)・App Group・bundle で同一名に統一している。
    /// ここを取り違えると報告が永久に端末へ反映されない silent failure になる。
    static let filename = "rules-reported.json"

    static func make() -> BlockerListResolver {
        BlockerListResolver(filterFilename: filename)
    }
}
