import Foundation
import SafariServices

/// CDN の popunder-rules.json を取得して App Group に保存し、popunder Extension を reload する。
/// 基本保護の更新と同じタイミング（前面復帰時・BGTask）で呼ぶ。best-effort（失敗は無視）。
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
        // CDN base が更新されたので combined-popunder を base 内容ハッシュ差分で作り直す
        // （reported>0 のユーザーが stale な combined に CDN 更新をマスクされるのを防ぐ）。
        CombinedRuleListCoordinator.scheduleRegenerate()
        // reported が空で combined が無いユーザー向けに、新 base を直読みさせる即時 reload も行う。
        await MainActor.run {
            SFContentBlockerManager.reloadContentBlocker(
                withIdentifier: SFContentBlockerStateChecker.popunderID
            ) { _ in }
        }
    }
}
