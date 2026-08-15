import XCTest
@testable import AdblockKeshi

/// iOS ↔ Workers の submit ペイロード契約テスト（クライアント側）。
///
/// `contracts/submit-request.json` を **両言語が同じ 1 ファイル**として突き合わせる。
/// サーバ側は `workers/tests/handlers/submit-contract.test.ts` が同じファイルを実際に POST して、
/// 全項目が D1 の想定カラムへ入ることを検証する。
/// 片側だけキー名を変えたら、どちらかが必ず落ちる。
final class SubmitContractTests: XCTestCase {

    private func loadContract() throws -> [String: Any] {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("contracts/submit-request.json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// 契約ファイルと同じ値で組んだ DTO が、キーも値も 1:1 で一致すること。
    func test_encodedDTO_matchesSharedContractFixture() throws {
        let contract = try loadContract()

        let dto = SubmitRequestDTO(
            token: try XCTUnwrap(contract["token"] as? String),
            uuidHash: try XCTUnwrap(contract["uuid_hash"] as? String),
            url: try XCTUnwrap(contract["url"] as? String),
            memo: contract["memo"] as? String,
            adType: contract["ad_type"] as? String,
            reportKind: try XCTUnwrap(contract["report_kind"] as? String),
            seenIn: contract["seen_in"] as? String,
            blockerEnabled: contract["blocker_enabled"] as? Bool,
            dnsEnabled: contract["dns_enabled"] as? Bool,
            appVersion: contract["app_version"] as? String,
            appBuild: contract["app_build"] as? String,
            filterVersion: contract["filter_version"] as? String
        )
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(dto)) as? [String: Any]
        )

        XCTAssertEqual(Set(encoded.keys), Set(contract.keys),
                       "契約ファイルと DTO のキー集合が一致しない")
        for key in contract.keys {
            XCTAssertEqual(String(describing: encoded[key]!), String(describing: contract[key]!),
                           "\(key) の値が契約と一致しない")
        }
    }

    /// 契約が使う `seen_in` は `SeenIn` の rawValue でなければならない。
    func test_contractSeenIn_isAValidSeenInRawValue() throws {
        let contract = try loadContract()
        let raw = try XCTUnwrap(contract["seen_in"] as? String)
        XCTAssertNotNil(SeenIn(rawValue: raw), "契約の seen_in が SeenIn に存在しない: \(raw)")
    }

    /// 契約が使う `ad_type` は `AdType` の rawValue でなければならない。
    func test_contractAdType_isAValidAdTypeRawValue() throws {
        let contract = try loadContract()
        let raw = try XCTUnwrap(contract["ad_type"] as? String)
        XCTAssertNotNil(AdType(rawValue: raw), "契約の ad_type が AdType に存在しない: \(raw)")
    }

    /// 契約が使う `report_kind` は `ReportKind` の rawValue でなければならない。
    func test_contractReportKind_isAValidReportKindRawValue() throws {
        let contract = try loadContract()
        let raw = try XCTUnwrap(contract["report_kind"] as? String)
        XCTAssertNotNil(ReportKind(rawValue: raw), "契約の report_kind が ReportKind に存在しない: \(raw)")
    }
}
