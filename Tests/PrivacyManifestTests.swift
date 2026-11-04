import XCTest

/// アプリ本体の PrivacyInfo.xcprivacy の申告が、ASC の「アプリのプライバシー」と実装に合っていることを守る。
/// 報告タブで送った時、サーバー（workers/src/handlers/submit.ts）が
/// 報告の内容（その他のユーザコンテンツ）・診断情報（その他の診断データ）・
/// 端末ごとの番号と送信元 IP のハッシュ（デバイス ID）を保存する。
final class PrivacyManifestTests: XCTestCase {

    private func loadManifest() throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "アプリ本体に PrivacyInfo.xcprivacy が入っていない"
        )
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    func test_declares_the_three_collected_data_types_matching_asc() throws {
        let manifest = try loadManifest()
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])

        let expected: Set<String> = [
            "NSPrivacyCollectedDataTypeDeviceID",
            "NSPrivacyCollectedDataTypeOtherDiagnosticData",
            "NSPrivacyCollectedDataTypeOtherUserContent",
        ]
        let actual = collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        XCTAssertEqual(Set(actual), expected)
        XCTAssertEqual(actual.count, expected.count, "同じ種類を二重に申告しない")
    }

    func test_each_collected_type_is_linked_not_tracking_and_for_app_functionality() throws {
        let manifest = try loadManifest()
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertFalse(collected.isEmpty)
        for entry in collected {
            let name = entry["NSPrivacyCollectedDataType"] as? String ?? "?"
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, true, "\(name): ユーザに関連付け＝あり")
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false, "\(name): トラッキング＝なし")
            XCTAssertEqual(
                entry["NSPrivacyCollectedDataTypePurposes"] as? [String],
                ["NSPrivacyCollectedDataTypePurposeAppFunctionality"],
                "\(name): 目的＝アプリの機能だけ"
            )
        }
    }

    func test_tracking_stays_off() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
    }
}
