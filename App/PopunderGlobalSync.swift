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
        await sync(
            download: { willReplace in (try? await downloader.downloadAndStore(willReplace: willReplace)) != nil },
            beginModification: { ContentBlockerReloader.shared.beginModification(SFContentBlockerStateChecker.popunderID) },
            regenerate: { CombinedRuleListCoordinator.scheduleRegenerate() },
            finishModification: {
                await ContentBlockerReloader.shared.finishModificationAndReload(SFContentBlockerStateChecker.popunderID)
            }
        )
    }

    /// 取得した中身が前と同じなら読み込まない（前面復帰のたびに約 5,000 万バイトのコンパイルを走らせない。
    /// 前回の読み込みが終わっていなければ ContentBlockerReloader の印が残っていて、そちらがやり直す）。
    /// 中身が変わるときは書き込みの前に印を付ける＝保存の後〜読み込みの前に終了されても次の起動で読み込み直す。
    static func sync(
        download: (_ willReplace: () async -> Void) async -> Bool,
        beginModification: @escaping @MainActor () -> Void,
        regenerate: () -> Void,
        finishModification: @MainActor () async -> Void
    ) async {
        var replacing = false
        let downloaded = await download {
            replacing = true
            await beginModification()
        }
        // 取得できたら毎回、combined の作り直しを予約する（4.4.0 までと同じ）。作り直しは入力の内容ハッシュで
        // 判定するので、変化が無ければ書き込みも読み込みも起きない。予約しないと、途中で止まった作り直しや、
        // 別ファイル（標準・残り）の差し替えで古くなった combined が、次の起動まで残る
        // （reported>0 のユーザーが stale な combined に CDN 更新をマスクされるのも防ぐ）。
        if downloaded || replacing { regenerate() }
        guard replacing else { return }
        // reported が空で combined が無いユーザー向けに、新 base を直読みさせる即時 reload も行う。
        // 書き込みが失敗しても、書き換えを始めた以上は印を付けたまま終わらせない。
        // 完了まで待つ＝バックグラウンド更新が時間切れで打ち切られたら、順番待ちの途中でも始めない。
        await finishModification()
    }
}
