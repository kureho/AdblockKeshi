import XCTest
@testable import AdblockKeshi

/// 診断情報の取得は **報告送信を絶対に止めてはいけない**。
/// `BestEffortValue.resolve` は「completion が来なければ期限で nil を返し、
/// 遅れて来た completion は無視する（continuation の二重 resume を起こさない）」を保証する。
final class BestEffortValueTests: XCTestCase {

    func test_returnsValue_whenCompletionArrivesInTime() async {
        let result: Bool? = await BestEffortValue.resolve(timeout: 1.0) { done in
            done(true)
        }
        XCTAssertEqual(result, true)
    }

    func test_returnsNil_whenCompletionNeverArrives() async {
        let started = Date()
        let result: Bool? = await BestEffortValue.resolve(timeout: 0.05) { _ in
            // わざと呼ばない（ハングした system API を模す）
        }
        XCTAssertNil(result, "期限内に返らなければ nil で送信を続行する")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0, "期限を大きく超えて待ってはいけない")
    }

    func test_lateCompletion_isIgnored_withoutCrashing() async {
        // 期限切れ後に completion が来ても二重 resume しない（クラッシュしない）。
        let result: String? = await BestEffortValue.resolve(timeout: 0.05) { done in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { done("late") }
        }
        XCTAssertNil(result)
        // 遅延 completion が走り切るまで待って、クラッシュしないことを確認する。
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    func test_completionPassingNil_isTreatedAsUnavailable() async {
        let result: Bool? = await BestEffortValue.resolve(timeout: 1.0) { done in
            done(nil)
        }
        XCTAssertNil(result)
    }
}
