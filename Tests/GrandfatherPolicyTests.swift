import XCTest
@testable import AdblockKeshi

/// GrandfatherPolicy（既存購入者の恒久 Pro 判定・純関数）のテスト。
/// canon: tasks/v4-freemium-dns-plan.md §grandfather 実装チェックリスト
final class GrandfatherPolicyTests: XCTestCase {

    func test_isLegacy_intComparison_notString_andEnvironmentGated() {
        let p = GrandfatherPolicy(conversionBuild: 10000, cutoffDate: Self.date("2026-07-01"))
        // 文字列比較なら "99" < "10000" が false になるバグを固定で防ぐ: build 99 は legacy
        XCTAssertTrue(p.isLegacy(originalBuild: "99", originalPurchaseDate: nil, environment: .production))
        XCTAssertTrue(p.isLegacy(originalBuild: "27", originalPurchaseDate: nil, environment: .production))
        XCTAssertFalse(p.isLegacy(originalBuild: "10000", originalPurchaseDate: nil, environment: .production))
        XCTAssertFalse(p.isLegacy(originalBuild: "10001", originalPurchaseDate: nil, environment: .production))
        // 審査/sandbox 環境（"1.0"）では常に false（購入導線を審査員に見せる）
        XCTAssertFalse(p.isLegacy(originalBuild: "1", originalPurchaseDate: nil, environment: .sandbox))
        // originalBuild 欠落でも purchaseDate が cutoff 以前なら legacy（補助判定・古い購入の救済）
        XCTAssertTrue(p.isLegacy(originalBuild: nil, originalPurchaseDate: Self.date("2026-06-01"), environment: .production))
    }

    func test_isLegacy_nonIntBuild_fallsBackToPurchaseDate() {
        let p = GrandfatherPolicy(conversionBuild: 10000, cutoffDate: Self.date("2026-07-01"))
        // "1.0" 形式（Int 化不能）でも purchaseDate 補助で救済
        XCTAssertTrue(p.isLegacy(originalBuild: "1.0", originalPurchaseDate: Self.date("2026-06-01"), environment: .production))
        // 補助も効かない（cutoff 以降）なら false
        XCTAssertFalse(p.isLegacy(originalBuild: "1.0", originalPurchaseDate: Self.date("2026-08-01"), environment: .production))
    }

    func test_isLegacy_bothMissing_isFalse() {
        let p = GrandfatherPolicy(conversionBuild: 10000, cutoffDate: Self.date("2026-07-01"))
        // build も date も無い → 過少付与に倒す（無料扱い）
        XCTAssertFalse(p.isLegacy(originalBuild: nil, originalPurchaseDate: nil, environment: .production))
    }

    func test_isLegacy_purchaseAfterCutoff_isNotLegacy() {
        let p = GrandfatherPolicy(conversionBuild: 10000, cutoffDate: Self.date("2026-07-01"))
        XCTAssertFalse(p.isLegacy(originalBuild: nil, originalPurchaseDate: Self.date("2026-07-02"), environment: .production))
    }

    static func date(_ ymd: String) -> Date {
        let parts = ymd.split(separator: "-").map { Int($0)! }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return Calendar(identifier: .gregorian).date(from: c)!
    }
}
