import Foundation
import SafariServices

/// グローバル配信された報告フィルタ(rules-reported.json)を取得して `rules-global.json` に保存し、
/// 自己報告(rules-self.json)とマージして報告Extension(reportedblocker)を reload する。
/// 標準フィルタ更新と同じタイミング（前面復帰時・BGTask）で呼ぶ。best-effort（失敗は無視）。
enum ReportedGlobalSync {
    static func sync() async {
        let downloader = FilterDownloader(
            blockerListURL: FilterDownloader.reportedURL,
            filename: SelfReportedRulesStore.globalFilename
        )
        guard (try? await downloader.downloadAndStore()) != nil else { return }
        try? SelfReportedRulesStore()?.rebuildMerged()
        await MainActor.run {
            SFContentBlockerManager.reloadContentBlocker(
                withIdentifier: SFContentBlockerStateChecker.reportedID
            ) { _ in }
        }
    }
}
