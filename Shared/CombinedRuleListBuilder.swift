import Foundation
import CryptoKit

/// 標準 variant + 安全化済み自己学習ルールを結合した `combined-<variant>` を App Group に生成する。
///
/// - **change-guard**: `(appBuildVersion, variant, reported のSHA256)` を meta に保存し、一致時は再生成しない
///   （変化なき起動で 19MB を作らない＝起動フリーズ/メモリスパイク回避）。
/// - **byte-splice**: truncation 不要 state は標準バイト列の末尾に reported を差し込む（full decode 回避）。
/// - **truncation**: ad-only（標準が上限ちょうど）のみ標準を decode して先頭 keep 件 + reported。
/// - **compile-verify → atomic write → last-known-good**: 検証失敗/書込失敗時は既存 combined を保持。
/// 重い処理は呼び出し側で off-main 実行する前提（本型は同期 IO）。設計は PHASE-B-design.md。
struct CombinedRuleListBuilder {
    let directory: URL
    let fileManager: FileManager
    let appBuildVersion: String

    init(directory: URL, fileManager: FileManager = .default, appBuildVersion: String) {
        self.directory = directory
        self.fileManager = fileManager
        self.appBuildVersion = appBuildVersion
    }

    init?(appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared",
          fileManager: FileManager = .default,
          appBuildVersion: String) {
        guard let container = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }
        self.directory = container
        self.fileManager = fileManager
        self.appBuildVersion = appBuildVersion
    }

    /// 標準 variant ファイル名（例 "merged-rules.json"）から combined ファイル名を導く。
    static func combinedFilename(forVariant variant: String) -> String { "combined-" + variant }

    struct Outcome: Equatable {
        var rebuilt: Bool
        var droppedStandard: Int
        var droppedReported: Int
    }

    /// 必要時のみ combined を再生成する。
    /// - Parameters:
    ///   - variantFilename: 標準 variant ファイル名（"merged-rules.json" 等）。
    ///   - standardRulesURL: 標準 variant ファイルの URL（App Group / bundle）。
    ///   - mayTruncate: ad-only（標準が上限ちょうど）なら true。false なら byte-splice。
    ///   - reportedSafe: 安全化済み・dedup 済み reported（報告順）。
    ///   - compileVerify: 生成データの検証（iOS: WKContentRuleListStore。テスト: stub）。throw すると install しない。
    /// - Returns: 再生成して install したら rebuilt=true（呼び出し側が reload）。変化なしは false。
    @discardableResult
    func rebuildIfNeeded(
        variantFilename: String,
        standardRulesURL: URL,
        mayTruncate: Bool,
        reportedSafe: [ContentBlockerRule],
        compileVerify: (Data) throws -> Void = { _ in }
    ) throws -> Outcome {
        let combinedName = Self.combinedFilename(forVariant: variantFilename)
        let combinedURL = directory.appendingPathComponent(combinedName)
        let metaURL = directory.appendingPathComponent(combinedName + ".meta")

        let reportedData = try JSONEncoder().encode(reportedSafe)
        let key = changeKey(variant: variantFilename, reportedData: reportedData)

        // change-guard: 入力が変わっておらず combined が既にあれば再生成しない（起動フリーズ回避）。
        if fileManager.fileExists(atPath: combinedURL.path),
           let existing = try? String(contentsOf: metaURL, encoding: .utf8),
           existing == key {
            return Outcome(rebuilt: false, droppedStandard: 0, droppedReported: 0)
        }

        let standardJSON = try Data(contentsOf: standardRulesURL)
        let combined: Data
        let droppedStandard: Int
        let droppedReported: Int
        if mayTruncate {
            // ad-only: 標準が上限ちょうど → decode して budget で先頭 keep 件 + reported。
            let standardRules = try JSONDecoder().decode([ContentBlockerRule].self, from: standardJSON)
            let plan = ReportedRuleBudget.plan(standardCount: standardRules.count, reportedSafe: reportedSafe)
            combined = try CombinedRuleListMerge.truncatedMerge(
                standardRules: standardRules, keepStandard: plan.standardKeep, reported: plan.reportedKeep)
            droppedStandard = plan.droppedStandard
            droppedReported = plan.droppedReported
        } else {
            // truncation 不要 state: byte-splice（標準を decode しない）。
            let sel = ReportedRuleBudget.selectReported(reportedSafe)
            combined = try CombinedRuleListMerge.splice(standardJSON: standardJSON, appending: sel.keep)
            droppedStandard = 0
            droppedReported = sel.dropped
        }

        // compile-verify → 失敗時は throw（既存 combined を保持＝last-known-good）。
        try compileVerify(combined)

        // atomic install（torn write 防止）→ meta 更新（combined 成功後）。
        try combined.write(to: combinedURL, options: [.atomic])
        try key.write(to: metaURL, atomically: true, encoding: .utf8)

        return Outcome(rebuilt: true, droppedStandard: droppedStandard, droppedReported: droppedReported)
    }

    private func changeKey(variant: String, reportedData: Data) -> String {
        // SHA256 は launch を跨いで安定（Swift の Hasher は per-run seed のため使わない）。
        // 標準 variant（ad/security/merged/empty-rules.json）は bundle 同梱で app version 毎に static
        // のため、appBuildVersion を鍵に含めれば標準の更新（= 新バージョン配布）も検知できる。
        let hex = SHA256.hash(data: reportedData).map { String(format: "%02x", $0) }.joined()
        return "\(appBuildVersion)|\(variant)|rep:\(reportedData.count):\(hex)"
    }
}
