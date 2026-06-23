import Foundation

/// 統合 Content Blocker のルール予算（純粋ロジック）。
///
/// 標準ルール + 安全化済み自己学習ルールを 1 リストに統合する際、WebKit の
/// 「1 拡張あたり 150,000 ルール」上限を超えないよう配分する。
/// - reported（自己学習）には固定予約枠（`reportedReserve`）を保証する。
/// - 標準ルールは reported が実際に占める分だけ削り、`standardFloor` 未満には削らない。
/// - combined は `totalCap`（= 上限 − 安全余白）を超えない。
/// 設計根拠は tasks/extension-consolidation/PHASE-B-design.md。
enum ReportedRuleBudget {
    static let webKitLimit = 150_000
    static let safetyMargin = 1_000
    static let totalCap = webKitLimit - safetyMargin        // 149,000
    static let reportedReserve = 2_000
    static let standardFloor = totalCap - reportedReserve   // 147,000

    struct Plan: Equatable {
        var standardKeep: Int
        var reportedKeep: [ContentBlockerRule]
        var droppedStandard: Int
        var droppedReported: Int
        var needsTruncation: Bool
        var combinedCount: Int { standardKeep + reportedKeep.count }
    }

    struct ReportedSelection: Equatable {
        var keep: [ContentBlockerRule]
        var dropped: Int
    }

    /// reported を予約枠（`reportedReserve`）内に収める。超過分は「新しさ」優先で
    /// insertion order の末尾（最近報告）を保持し、古いものを drop する。標準件数に依存しない
    /// （byte-splice 経路で標準を decode せずに使える）。
    static func selectReported(_ reportedSafe: [ContentBlockerRule]) -> ReportedSelection {
        if reportedSafe.count > reportedReserve {
            return ReportedSelection(keep: Array(reportedSafe.suffix(reportedReserve)),
                                     dropped: reportedSafe.count - reportedReserve)
        }
        return ReportedSelection(keep: reportedSafe, dropped: 0)
    }

    /// - Parameters:
    ///   - standardCount: 標準 variant のルール数。
    ///   - reportedSafe: 既に safety filter + structural dedup 済みの自己学習ルール（報告順 = oldest→newest）。
    /// - Returns: 標準を何件残すか、reported をどれだけ採用するか（新しさ優先）。
    static func plan(standardCount: Int, reportedSafe: [ContentBlockerRule]) -> Plan {
        // reported: 予約枠を超えたら「新しさ」優先（insertion order の末尾＝最近報告）で採用。
        let sel = selectReported(reportedSafe)

        // 標準: reported が実際に占める分だけ削る。floor（standardFloor）未満には削らない
        // （sel.keep.count ≤ reportedReserve なので totalCap − sel.keep.count ≥ standardFloor）。
        let standardKeep = min(standardCount, totalCap - sel.keep.count)
        let droppedStandard = standardCount - standardKeep

        return Plan(
            standardKeep: standardKeep,
            reportedKeep: sel.keep,
            droppedStandard: droppedStandard,
            droppedReported: sel.dropped,
            needsTruncation: droppedStandard > 0
        )
    }
}
