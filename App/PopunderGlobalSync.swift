import Foundation
import SafariServices

/// CDN の popunder-rules.json を取得して App Group に保存し、popunder Extension を reload する。
/// 標準フィルタ更新と同じタイミング（前面復帰時・BGTask）で呼ぶ。best-effort（失敗は無視）。
///
/// `PopunderRulesResolver` は App Group の `popunder-rules.json` を優先し、無ければ bundle 同梱版に
/// フォールバックするため、ここで App Group に最新版を落とすと審査なしで反映できる（living list）。
/// version 同期はしない（popunder は「最終更新日」UI を持たず、本体 version.json を上書きしないため）。
enum PopunderGlobalSync {
    static let cdnURL = URL(string: "https://kureho.github.io/AdblockKeshi/cdn/popunder-rules.json")!

    static func sync() async {
        let downloader = FilterDownloader(
            blockerListURL: cdnURL,
            filename: PopunderRulesResolver.filename,
            syncsVersion: false
        )
        guard (try? await downloader.downloadAndStore()) != nil else { return }
        await MainActor.run {
            SFContentBlockerManager.reloadContentBlocker(
                withIdentifier: SFContentBlockerStateChecker.popunderID
            ) { _ in }
        }
    }
}
