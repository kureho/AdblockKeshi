import XCTest
@testable import AdblockKeshi

/// D-lite で `applied_locally`（端末即反映）は無くなる。
/// しかし既存端末の履歴（UserDefaults）にはその値が保存されている。
/// 素直に case を消すと decode が throw し、`LocalReportHistoryStore` の
/// fail-safe が働いて **履歴が丸ごと消える**。
/// 未知の値は `.pending`（受付済）へ寄せて、履歴を失わないことを固定する。
final class ReportStatusLegacyDecodeTests: XCTestCase {

    private func decodeStatus(_ raw: String) throws -> ReportStatus {
        let json = Data("[\"\(raw)\"]".utf8)
        return try JSONDecoder().decode([ReportStatus].self, from: json)[0]
    }

    func test_legacyAppliedLocally_decodesAsPending() throws {
        XCTAssertEqual(try decodeStatus("applied_locally"), .pending)
    }

    func test_unknownStatus_decodesAsPending() throws {
        XCTAssertEqual(try decodeStatus("some_future_status"), .pending)
    }

    func test_knownStatuses_roundTrip() throws {
        for status in ReportStatus.allCases {
            XCTAssertEqual(try decodeStatus(status.rawValue), status)
        }
    }

    func test_appliedLocally_isNoLongerACase() {
        XCTAssertFalse(ReportStatus.allCases.map(\.rawValue).contains("applied_locally"))
    }

    /// 既存履歴（applied_locally 入り）を読んでも失われない。
    func test_storedHistoryWithLegacyStatus_survivesLoad() throws {
        let suite = "dlite.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let legacy = """
        [{"id":"1","url":"https://ads.example.com/a","memo_redacted":false,\
        "status":"applied_locally","created_at":1785542400,"applied_at":1785542400}]
        """
        defaults.set(Data(legacy.utf8), forKey: LocalReportHistoryStore.storageKey)

        let items = try JSONDecoder().decode(
            [ReportHistoryItem].self,
            from: defaults.data(forKey: LocalReportHistoryStore.storageKey)!
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].status, .pending)
    }
}

/// 表示文言に「この端末で即ブロック」系が残っていないこと。
final class ReportStatusWordingTests: XCTestCase {

    private static let forbiddenFragments = [
        "この端末で反映",
        "この端末ではすぐに",
        "即ブロック",
        "すぐにブロック",
    ]

    func test_noStatusText_promisesImmediateLocalBlocking() {
        for status in ReportStatus.allCases {
            for fragment in Self.forbiddenFragments {
                XCTAssertFalse(status.displayLabel.contains(fragment),
                               "\(status).displayLabel に「\(fragment)」が残っている")
                XCTAssertFalse(status.detailDescription.contains(fragment),
                               "\(status).detailDescription に「\(fragment)」が残っている")
            }
        }
    }
}
