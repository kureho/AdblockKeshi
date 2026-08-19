import XCTest
@testable import AdblockKeshi

/// `SubmitRequestDTO` のキー名は Workers の `SubmitBody`
/// (`workers/src/handlers/submit.ts`) と 1:1 で一致していなければならない。
/// nil の項目は **キーごと省略**する（サーバは未指定を NULL として扱う）。
final class SubmitRequestDTOEncodingTests: XCTestCase {

    private func encode(_ dto: SubmitRequestDTO) throws -> [String: Any] {
        let data = try JSONEncoder().encode(dto)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fullDTO() -> SubmitRequestDTO {
        SubmitRequestDTO(
            token: "tok",
            uuidHash: String(repeating: "a", count: 64),
            url: "https://example.com/article",
            memo: "メモ",
            adType: "popup",
            reportKind: "site_broken",
            seenIn: "safari",
            blockerEnabled: true,
            dnsEnabled: false,
            appVersion: "4.1.0",
            appBuild: "10004",
            filterVersion: "2026-08-01"
        )
    }

    func test_keys_matchWorkersContract() throws {
        let json = try encode(fullDTO())

        XCTAssertEqual(json["token"] as? String, "tok")
        XCTAssertEqual(json["uuid_hash"] as? String, String(repeating: "a", count: 64))
        XCTAssertEqual(json["url"] as? String, "https://example.com/article")
        XCTAssertEqual(json["memo"] as? String, "メモ")
        XCTAssertEqual(json["ad_type"] as? String, "popup")
        XCTAssertEqual(json["report_kind"] as? String, "site_broken")
        XCTAssertEqual(json["seen_in"] as? String, "safari")
        XCTAssertEqual(json["blocker_enabled"] as? Bool, true)
        XCTAssertEqual(json["dns_enabled"] as? Bool, false)
        XCTAssertEqual(json["app_version"] as? String, "4.1.0")
        XCTAssertEqual(json["app_build"] as? String, "10004")
        XCTAssertEqual(json["filter_version"] as? String, "2026-08-01")
    }

    func test_noUnexpectedKeys() throws {
        let json = try encode(fullDTO())
        XCTAssertEqual(
            Set(json.keys),
            ["token", "uuid_hash", "url", "memo", "ad_type", "report_kind", "seen_in",
             "blocker_enabled", "dns_enabled", "app_version", "app_build", "filter_version"]
        )
    }

    func test_nilDiagnostics_areOmittedEntirely() throws {
        let dto = SubmitRequestDTO(
            token: "tok",
            uuidHash: String(repeating: "a", count: 64),
            url: "https://example.com/article",
            memo: nil,
            adType: nil,
            reportKind: "ad_not_blocked",
            seenIn: "other_app",
            blockerEnabled: nil,
            dnsEnabled: nil,
            appVersion: nil,
            appBuild: nil,
            filterVersion: nil
        )
        let json = try encode(dto)

        XCTAssertEqual(Set(json.keys), ["token", "uuid_hash", "url", "report_kind", "seen_in"],
                       "report_kind は新クライアントでは常に送る（旧サーバは無視するので、"
                       + "site_broken を誤学習させないために workers deploy を先に済ませる）")
        for omitted in ["memo", "ad_type", "blocker_enabled", "dns_enabled",
                        "app_version", "app_build", "filter_version"] {
            XCTAssertNil(json[omitted], "\(omitted) は nil ならキーごと省略する")
        }
    }

    /// `blocker_enabled=false` は「未取得」ではなく「無効だった」。
    /// 省略されると診断価値が消えるので、false は必ず送る。
    func test_falseFlags_areSentNotOmitted() throws {
        let dto = SubmitRequestDTO(
            token: "tok", uuidHash: String(repeating: "a", count: 64),
            url: "https://example.com/a", memo: nil, adType: nil,
            reportKind: "ad_not_blocked", seenIn: "safari",
            blockerEnabled: false, dnsEnabled: false,
            appVersion: nil, appBuild: nil, filterVersion: nil
        )
        let json = try encode(dto)
        XCTAssertEqual(json["blocker_enabled"] as? Bool, false)
        XCTAssertEqual(json["dns_enabled"] as? Bool, false)
    }
}
