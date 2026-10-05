import XCTest
@testable import AdblockKeshi

/// 同梱のルールは、通信できない初回などに拡張が Safari へそのまま渡す。上限（ReportedRuleBudget.maxListBytes）を
/// 超えると実機で拡張がメモリ上限により強制終了し、Safari に何も入らない（2026-10-05・4.4.0〜4.4.1 の同梱 27.0MB）。
/// シミュレータには拡張のメモリ上限が無いので、動かして確かめても見つからない＝大きさで縛る。
final class BundledRuleListSizeTests: XCTestCase {

    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    private func size(_ path: String) throws -> Int {
        try Data(contentsOf: repoRoot.appendingPathComponent(path)).count
    }

    func test_基本保護の同梱ルールは拡張が渡せる大きさに収まる() throws {
        for path in ["Extension/Resources/merged-rules.json",
                     "Extension/Resources/ad-rules.json",
                     "Extension/Resources/security-rules.json"] {
            XCTAssertLessThanOrEqual(try size(path), ReportedRuleBudget.maxListBytes, path)
        }
    }

    /// 2 本目は「残り → ポップアップ対策 → 報告 → 一時オフ」を繋いで渡す。報告と一時オフは組み立て側（CombinedRuleListBuilder）が上限で止める。
    func test_2本目の同梱の残りはポップアップ対策を繋いでも拡張が渡せる大きさに収まる() throws {
        let popunder = try size("PopunderBlockerExtension/Resources/popunder-rules.json")
        for path in ["App/Resources/second-ads-sec.json", "App/Resources/second-ads.json"] {
            XCTAssertLessThanOrEqual(try size(path) + popunder, ReportedRuleBudget.maxListBytes, path)
        }
    }

    /// 広告だけ ON の人が一時オフを上限（200 サイト）まで入れても、基本保護の combined は上限に収まり、一時オフも落ちない。
    /// 書き直しで「/」が「\/」になると同梱 19.5MB が約 45 万バイト膨らみ、ここで上限を超えていた（Codex 指摘 2026-10-05）。
    func test_広告だけの基本保護は一時オフを上限まで足しても拡張が渡せる大きさに収まる() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let longest = (0..<SiteExceptionsStore.maxDomains).map { String(repeating: "a", count: 240) + "\(1000 + $0).example" }
        let out = try CombinedRuleListBuilder(directory: dir, appBuildVersion: "test")
            .rebuildIfNeeded(variantFilename: "ad-rules.json",
                             standardRulesURL: repoRoot.appendingPathComponent("Extension/Resources/ad-rules.json"),
                             mayTruncate: true, reportedSafe: SiteExceptionRules.rules(for: longest))
        XCTAssertTrue(out.rebuilt)
        XCTAssertEqual(out.droppedReported, 0)
        XCTAssertLessThanOrEqual(try Data(contentsOf: dir.appendingPathComponent("combined-ad-rules.json")).count,
                                 ReportedRuleBudget.maxListBytes)
    }
}

