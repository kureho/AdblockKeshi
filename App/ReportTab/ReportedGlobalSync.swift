import Foundation

/// グローバル配信された報告フィルタ(rules-reported.json)を取得して `rules-global.json` に保存し、
/// 自己報告(rules-self.json)とマージ後、統合 ContentBlocker の combined を再生成して標準を reload する。
/// 基本保護の更新と同じタイミング（前面復帰時・BGTask）で呼ぶ。best-effort（失敗は無視）。
/// 4→3 統合後、自己学習は標準 ContentBlocker に統合された（旧 reportedblocker は廃止）。
enum ReportedGlobalSync {
    static func sync() async {
        let downloader = FilterDownloader(
            blockerListURL: FilterDownloader.reportedURL,
            filename: SelfReportedRulesStore.globalFilename
        )
        guard (try? await downloader.downloadAndStore()) != nil else { return }
        try? SelfReportedRulesStore()?.rebuildMerged()
        // combined を再生成（off-main）して標準 ContentBlocker を reload。
        CombinedRuleListCoordinator.scheduleRegenerate()
    }
}
