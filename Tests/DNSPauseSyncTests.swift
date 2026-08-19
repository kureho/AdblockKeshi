import XCTest
@testable import AdblockKeshi

/// v4.2.0: 一時停止の取りこぼし回収。
/// reload 通知（sendProviderMessage）は落ちうるので、tick が App Group の実体と突き合わせる。
final class DNSPauseSyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private var future: Date { now.addingTimeInterval(600) }
    private var past: Date { now.addingTimeInterval(-1) }

    func test_none_whenBothIdle() {
        XCTAssertEqual(DNSPauseSync.decide(current: nil, stored: nil, now: now), .none)
    }

    func test_none_whenBothHoldSameDeadline() {
        XCTAssertEqual(DNSPauseSync.decide(current: future, stored: future, now: now), .none)
    }

    /// アプリが停止を書いたのに reload 通知が届かなかった＝ブロックし続けている状態。
    func test_reload_whenAppPausedButProviderDidNotHear() {
        XCTAssertEqual(DNSPauseSync.decide(current: nil, stored: future, now: now), .reload)
    }

    /// アプリが解除したのに通知が届かなかった＝素通しのまま保護が戻らない状態。
    func test_reload_whenAppResumedButProviderDidNotHear() {
        XCTAssertEqual(DNSPauseSync.decide(current: future, stored: nil, now: now), .reload)
    }

    /// 停止時間を選び直した（15分 → 1時間）ケースも実体に合わせ直す。
    func test_reload_whenDeadlineChanged() {
        let other = now.addingTimeInterval(3600)
        XCTAssertEqual(DNSPauseSync.decide(current: future, stored: other, now: now), .reload)
    }

    /// 期限切れは「ずれ」ではなく自動再開として扱う（clear まで走らせる必要がある）。
    func test_resumeExpired_whenDeadlinePassed() {
        XCTAssertEqual(DNSPauseSync.decide(current: past, stored: nil, now: now), .resumeExpired)
    }

    /// 境界: now == 期限ちょうどは再開側に倒す（保護が生きる方向）。
    func test_resumeExpired_atExactDeadline() {
        XCTAssertEqual(DNSPauseSync.decide(current: now, stored: nil, now: now), .resumeExpired)
    }
}
