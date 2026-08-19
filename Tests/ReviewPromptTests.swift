import XCTest
@testable import AdblockKeshi

/// ReviewPrompt v2 の発火条件テスト。
/// 仕様: docs/superpowers/specs/2026-06-11-review-prompt-v2-design.md §3.1 / §4
/// 2026-07-15: 発火閾値を [7,23,58] → [3,13,34] に引き下げ（満足ユーザーを離脱前に捕捉するため）。
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

    // 1. 第一閾値(3)未到達では発火しない
    func test_doesNotFire_belowFirstThreshold() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 2, at: base + 10 * day, fired: &fired)
        XCTAssertEqual(fired, 0)
    }

    // 2. count=3 到達・全条件 OK で発火する
    func test_fires_atFirstThreshold_whenAllConditionsMet() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 3, at: base + 10 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
    }

    // 3. 初回起動 3 日未満では発火せず、3 日経過後の次の bump で持ち越し発火する
    func test_carriesOver_whenWithinFirstLaunchGrace() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 3, at: base + 1 * day, fired: &fired)
        XCTAssertEqual(fired, 0)
        bump(times: 1, at: base + 4 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
    }

    // 4. クールダウン 90 日内では次の閾値を跨いでも発火しない / 経過後の bump で発火する
    func test_respectsCooldown_thenFiresAfterCooldown() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 3, at: base + 10 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // count 4〜13: 閾値 13 を跨ぐがクールダウン内なので発火しない
        bump(times: 10, at: base + 20 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // クールダウン経過後の bump で持ち越し発火
        bump(times: 1, at: base + 101 * day, fired: &fired)
        XCTAssertEqual(fired, 2)
    }

    // 5. blocked=true（広告予約中）は持ち越し、次の blocked=false の bump で発火する
    func test_blockedCarriesOver_firesOnNextUnblockedBump() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 3, at: base + 10 * day, blocked: true, fired: &fired)
        XCTAssertEqual(fired, 0)
        bump(times: 1, at: base + 10 * day, blocked: false, fired: &fired)
        XCTAssertEqual(fired, 1)
    }

    // 6. ネガティブイベント後 7 日間は発火しない / 経過後の bump で発火する
    func test_suppressesAfterNegativeEvent_thenRecovers() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        ReviewPrompt.recordNegativeEvent(defaults: defaults, now: base + 10 * day)
        var fired = 0
        bump(times: 3, at: base + 12 * day, fired: &fired)
        XCTAssertEqual(fired, 0)
        bump(times: 1, at: base + 18 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
    }

    // 7. 発火済み閾値では再発火せず、次の閾値到達まで発火しない
    func test_firesOncePerThreshold() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 3, at: base + 10 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // クールダウンを完全に外しても、count 4〜12 では発火しない
        bump(times: 9, at: base + 200 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // 13 個目で発火
        bump(times: 1, at: base + 200 * day, fired: &fired)
        XCTAssertEqual(fired, 2)
    }

    // 8. v1 からの移行: 全閾値超過の既存ユーザーは次の bump で 1 回だけ発火し、以後は再発火しない
    func test_migration_existingUserFiresOnceOnNextBump() {
        // v1 が残した状態を再現（firedThresholds キーは存在しない・count は全閾値超過）
        defaults.set(50, forKey: "reviewPrompt.successCount")
        defaults.set(base, forKey: "reviewPrompt.firstLaunchDate")
        var fired = 0
        bump(times: 1, at: base + 100 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // 直後の bump（通過済み閾値は消化済み）では発火しない
        bump(times: 1, at: base + 100 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
        // ★v3 (2026-08) で意図的に変更: 全閾値消化済みのこの層こそ「評価リセット後の再依頼」の
        // 対象なので、クールダウン明けに一度だけ発火する（v2 では「二度と発火しない」だった）。
        bump(times: 10, at: base + 300 * day, fired: &fired)
        XCTAssertEqual(fired, 2, "リセット後の再依頼が 1 回だけ乗る")
        // その先は一回限りフラグが効いて二度と出ない
        bump(times: 10, at: base + 500 * day, fired: &fired)
        XCTAssertEqual(fired, 2)
    }

    // 9. 境界値: 初回起動からちょうど 3 日で発火する（>= 判定）
    func test_fires_atExactly3DaysSinceFirstLaunch() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 3, at: base + 3 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
    }

    // 10. 境界値: クールダウンちょうど 90 日経過で発火する（< 判定の補集合）
    func test_fires_atExactly90DaysCooldown() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 13, at: base + 10 * day, fired: &fired) // 3 で発火、13 は持ち越し
        XCTAssertEqual(fired, 1)
        bump(times: 1, at: base + 100 * day, fired: &fired) // 10+90 日ちょうど
        XCTAssertEqual(fired, 2)
    }

    // 11. 境界値: ネガティブイベントからちょうど 7 日で発火する
    func test_fires_atExactly7DaysAfterNegative() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        ReviewPrompt.recordNegativeEvent(defaults: defaults, now: base + 10 * day)
        var fired = 0
        bump(times: 3, at: base + 12 * day, fired: &fired)
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
        bump(times: 3, at: base + 3 * day, fired: &fired)
        XCTAssertEqual(fired, 1)
    }

    // MARK: - 閾値移行（[7,23,58] → [3,13,34]・重複プロンプト防止）

    private let kFired = "reviewPrompt.firedThresholds"

    func test_migration_mapsOldFiredThresholdsToNewPositions() {
        defaults.set([7, 23], forKey: kFired)   // 旧の第1・第2閾値を発火済み
        ReviewPrompt.migrateThresholdsIfNeeded(defaults: defaults)
        // 新の同位置（3, 13）に移行され、重複発火しない
        let fired = Set(defaults.array(forKey: kFired) as? [Int] ?? [])
        XCTAssertEqual(fired, [3, 13])
    }

    func test_migration_runsOnlyOnce_andDoesNotRemapNewValues() {
        defaults.set([58], forKey: kFired)   // 旧の第3閾値
        ReviewPrompt.migrateThresholdsIfNeeded(defaults: defaults)
        XCTAssertEqual(Set(defaults.array(forKey: kFired) as? [Int] ?? []), [34])
        // 2回目は何もしない（新値 34 を旧扱いして再マップしない）
        ReviewPrompt.migrateThresholdsIfNeeded(defaults: defaults)
        XCTAssertEqual(Set(defaults.array(forKey: kFired) as? [Int] ?? []), [34])
    }

    func test_migration_noFired_isNoop() {
        ReviewPrompt.migrateThresholdsIfNeeded(defaults: defaults)
        XCTAssertNil(defaults.array(forKey: kFired))
    }

    // MARK: - v3: 評価リセット後の一回限り再依頼（reviewPrompt.postResetReask2026）

    /// 全閾値 [3,13,34] を消化し、「通常発火の余地が無い」状態を作る。
    /// 4.1.0 の評価リセットで★が消えた既存ユーザーがこの状態にいる。
    /// - Returns: 最後の通常発火が起きた時刻
    @discardableResult
    private func consumeAllThresholds() -> Date {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 3, at: base + 10 * day, fired: &fired)    // 閾値 3
        bump(times: 10, at: base + 110 * day, fired: &fired)  // 閾値 13（クールダウン明け）
        bump(times: 21, at: base + 210 * day, fired: &fired)  // 閾値 34
        XCTAssertEqual(fired, 3, "前提: 通常発火が 3 回とも起きていること")
        return base + 210 * day
    }

    // v3-1. 全閾値消化済みでも、クールダウン明けに一度だけ再依頼が発火する
    func test_postResetReask_firesOnce_afterAllThresholdsConsumed() {
        let last = consumeAllThresholds()
        var fired = 0
        bump(times: 1, at: last + 100 * day, fired: &fired)
        XCTAssertEqual(fired, 1, "リセット後の再依頼が 1 回発火する")
    }

    // v3-2. 再依頼は一回限り（フラグ永続）。さらに 90 日経っても 2 回目は無い
    func test_postResetReask_doesNotFireTwice() {
        let last = consumeAllThresholds()
        var fired = 0
        bump(times: 1, at: last + 100 * day, fired: &fired)
        XCTAssertEqual(fired, 1)

        var again = 0
        bump(times: 5, at: last + 300 * day, fired: &again)
        XCTAssertEqual(again, 0, "一回限りフラグが永続するので 2 回目は発火しない")
    }

    // v3-3. 90 日クールダウン中は再依頼も発火しない（既存ガードを迂回しない）
    func test_postResetReask_respectsCooldown() {
        let last = consumeAllThresholds()
        var fired = 0
        bump(times: 3, at: last + 10 * day, fired: &fired)
        XCTAssertEqual(fired, 0, "クールダウン中は再依頼も出さない")
    }

    // v3-4. ネガティブ体験から 7 日以内は再依頼も発火しない
    func test_postResetReask_respectsNegativeSuppression() {
        let last = consumeAllThresholds()
        ReviewPrompt.recordNegativeEvent(defaults: defaults, now: last + 98 * day)
        var fired = 0
        bump(times: 3, at: last + 100 * day, fired: &fired)
        XCTAssertEqual(fired, 0, "ネガティブ抑止中は再依頼も出さない")
    }

    // v3-5. 通常発火がまだ残っている段階では再依頼フラグを消費しない
    func test_postResetReask_doesNotConsumeFlag_whileNormalThresholdsRemain() {
        ReviewPrompt.recordFirstLaunchIfNeeded(defaults: defaults, now: base)
        var fired = 0
        bump(times: 3, at: base + 10 * day, fired: &fired)    // 閾値 3 で通常発火
        XCTAssertEqual(fired, 1)
        // ここで再依頼フラグが消費されていたら、全閾値消化後の再依頼が出なくなる
        bump(times: 10, at: base + 110 * day, fired: &fired)  // 閾値 13
        bump(times: 21, at: base + 210 * day, fired: &fired)  // 閾値 34
        XCTAssertEqual(fired, 3)

        var reask = 0
        bump(times: 1, at: base + 310 * day, fired: &reask)
        XCTAssertEqual(reask, 1, "通常発火はフラグを消費しないので再依頼が残っている")
    }
}
