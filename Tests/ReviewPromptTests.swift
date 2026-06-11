import XCTest
@testable import AdblockKeshi

/// ReviewPrompt v2 の発火条件テスト。
/// 仕様: docs/superpowers/specs/2026-06-11-review-prompt-v2-design.md §3.1 / §4
@MainActor
final class ReviewPromptTests: XCTestCase {
    private let suiteName = "ReviewPromptTests"
    private var defaults: UserDefaults!
    private let day: TimeInterval = 86_400
    /// 固定基準時刻（テストの再現性のため Date() は使わない）
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    /// 初回起動を記録し、以降の bump をまとめて実行するヘルパ
    private func bump(times: Int, at date: Date, blocked: Bool = false, fired: inout Int) {
        for _ in 0..<times {
            var didFire = false
            ReviewPrompt.bumpAndMaybeRequest(blocked: blocked, defaults: defaults, now: date) {
                didFire = true
            }
            if didFire { fired += 1 }
        }
    }

    // 1. 閾値未到達では発火しない
    func test_doesNotFire_belowFirstThreshold() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 6, at: base + 10 * day, fired: &fired)
        XCTAssertEqual(fired, 0)
    }

    // 2. count=7 到達・全条件 OK で発火する
    func test_fires_atFirstThreshold_whenAllConditionsMet() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 7, at: base + 10 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
    }

    // 3. 初回起動 3 日未満では発火せず、3 日経過後の次の bump で持ち越し発火する
    func test_carriesOver_whenWithinFirstLaunchGrace() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 7, at: base + 1 * day, fired: &fired)
        XCTAssertEqual(fired, 0)
        bump(times: 1, at: base + 4 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
    }

    // 4. クールダウン 90 日内では次の閾値を跨いでも発火しない / 経過後の bump で発火する
    func test_respectsCooldown_thenFiresAfterCooldown() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 7, at: base + 10 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // count 8〜23: 閾値 23 を跨ぐがクールダウン内なので発火しない
        bump(times: 16, at: base + 20 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // クールダウン経過後の bump で持ち越し発火
        bump(times: 1, at: base + 101 * day, fired: &fired)
        XCTAssertEqual(fired, 2)
    }

    // 5. blocked=true（広告予約中）は持ち越し、次の blocked=false の bump で発火する
    func test_blockedCarriesOver_firesOnNextUnblockedBump() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 7, at: base + 10 * day, blocked: true, fired: &fired)
        XCTAssertEqual(fired, 0)
        bump(times: 1, at: base + 10 * day, blocked: false, fired: &fired)
        XCTAssertEqual(fired, 1)
    }

    // 6. ネガティブイベント後 7 日間は発火しない / 経過後の bump で発火する
    func test_suppressesAfterNegativeEvent_thenRecovers() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        ReviewPrompt.recordNegativeEvent(defaults: defaults, now: base + 10 * day)
        var fired = 0
        bump(times: 7, at: base + 12 * day, fired: &fired)
        XCTAssertEqual(fired, 0)
        bump(times: 1, at: base + 18 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
    }

    // 7. 発火済み閾値では再発火せず、次の閾値到達まで発火しない
    func test_firesOncePerThreshold() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 7, at: base + 10 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // クールダウンを完全に外しても、count 8〜22 では発火しない
        bump(times: 15, at: base + 200 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // 23 個目で発火
        bump(times: 1, at: base + 200 * day, fired: &fired)
        XCTAssertEqual(fired, 2)
    }

    // 8. v1 からの移行: count 既超過の既存ユーザーは次の bump で 1 回だけ発火し、通過済み閾値が消化される
    func test_migration_existingUserFiresOnceOnNextBump() {
        // v1 が残した状態を再現（firedThresholds キーは存在しない）
        defaults.set(50, forKey: "reviewPrompt.successCount")
        defaults.set(base, forKey: "reviewPrompt.firstLaunchDate")
        var fired = 0
        bump(times: 1, at: base + 100 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // 直後の bump（count=52, 通過済み閾値は消化済み・58 未到達）では発火しない
        bump(times: 1, at: base + 100 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // 58 は未消化で残っており、クールダウン経過 + 58 到達で発火する
        bump(times: 5, at: base + 200 * day, fired: &fired) // count 53...57
        XCTAssertEqual(fired, 1)
        bump(times: 1, at: base + 200 * day, fired: &fired) // count 58
        XCTAssertEqual(fired, 2)
    }

    // 9. 境界値: 初回起動からちょうど 3 日で発火する（>= 判定）
    func test_fires_atExactly3DaysSinceFirstLaunch() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 7, at: base + 3 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
    }

    // 10. 境界値: クールダウンちょうど 90 日経過で発火する（< 判定の補集合）
    func test_fires_atExactly90DaysCooldown() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 23, at: base + 10 * day, fired: &fired) // 7 で発火、23 は持ち越し
        XCTAssertEqual(fired, 1)
        bump(times: 1, at: base + 100 * day, fired: &fired) // 10+90 日ちょうど
        XCTAssertEqual(fired, 2)
    }

    // 11. 境界値: ネガティブイベントからちょうど 7 日で発火する
    func test_fires_atExactly7DaysAfterNegative() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        ReviewPrompt.recordNegativeEvent(defaults: defaults, now: base + 10 * day)
        var fired = 0
        bump(times: 7, at: base + 12 * day, fired: &fired)
        XCTAssertEqual(fired, 0)
        bump(times: 1, at: base + 17 * day, fired: &fired) // 10+7 日ちょうど
        XCTAssertEqual(fired, 1)
    }

    // 12. 初回起動が未記録なら count をいくら積んでも発火しない（暗黙仕様の文書化）
    func test_neverFires_whenFirstLaunchNotRecorded() {
        var fired = 0
        bump(times: 60, at: base + 100 * day, fired: &fired)
        XCTAssertEqual(fired, 0)
    }

    // 13. recordFirstLaunchIfNeeded は冪等（2 回目で日付を上書きしない）
    func test_recordFirstLaunchIfNeeded_isIdempotent() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base + 10 * day)
        // 初回日付が base のままなら base+3日 の bump で発火する
        var fired = 0
        bump(times: 7, at: base + 3 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
    }
}
