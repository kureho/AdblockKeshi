import XCTest
@testable import AdblockKeshi

/// `SeenIn` はサーバ (`workers/src/lib/seen-in.ts` の `SEEN_IN_VALUES`) と
/// **完全同期**していなければならない。ここがずれると submit が
/// `seen_in` を認識できず、報告が `observation_legacy`（旧クライアント扱い）に
/// 落ちて自動改善の母集団から外れる。
final class SeenInTests: XCTestCase {

    func test_rawValues_matchWorkersContract() {
        XCTAssertEqual(SeenIn.safari.rawValue, "safari")
        XCTAssertEqual(SeenIn.otherApp.rawValue, "other_app")
    }

    func test_allCases_orderAndCount() {
        XCTAssertEqual(SeenIn.allCases.map(\.rawValue), ["safari", "other_app"])
    }

    func test_everyCase_hasUserFacingText() {
        for value in SeenIn.allCases {
            XCTAssertFalse(value.title.isEmpty, "\(value) に見出しが無い")
            XCTAssertFalse(value.detail.isEmpty, "\(value) に補足が無い")
            XCTAssertFalse(value.iconSystemName.isEmpty, "\(value) にアイコンが無い")
        }
    }

    /// Safari 以外は「Safari 用フィルタでは消せない」ことを送信後に伝える必要がある。
    func test_onlySafari_isCoveredByContentBlocker() {
        XCTAssertTrue(SeenIn.safari.isCoveredByContentBlocker)
        XCTAssertFalse(SeenIn.otherApp.isCoveredByContentBlocker)
    }
}
