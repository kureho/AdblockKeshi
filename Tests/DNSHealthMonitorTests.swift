import XCTest
@testable import AdblockKeshi

/// DNSHealthMonitor（watchdog フェイルセーフの判定機）のテスト。
/// 4.0.1 hotfix: 上流が無応答なら rotate、全上流を使い切ったら stopTunnel = 「端末のネットが死んだまま」を構造的に防ぐ。
/// 判定は純ロジック（時刻は引数注入・タイマー/I/O は Provider 側）。
final class DNSHealthMonitorTests: XCTestCase {

    // minUnansweredQueries: 3 / window: 6 秒 / upstreamCount: 可変

    private func monitor(upstreamCount: Int) -> DNSHealthMonitor {
        DNSHealthMonitor(minUnansweredQueries: 3, window: 6, upstreamCount: upstreamCount)
    }

    func test_initially_none() {
        XCTAssertEqual(monitor(upstreamCount: 2).check(now: 100), .none)
    }

    func test_fewUnansweredQueries_none_evenAfterWindow() {
        let m = monitor(upstreamCount: 2)
        m.recordForward(now: 100)
        m.recordForward(now: 101)
        XCTAssertEqual(m.check(now: 110), .none, "閾値未満（2件）は静かな回線と区別できないので発火しない")
    }

    func test_manyUnanswered_butWindowNotElapsed_none() {
        let m = monitor(upstreamCount: 2)
        m.recordForward(now: 100)
        m.recordForward(now: 100.1)
        m.recordForward(now: 100.2)
        XCTAssertEqual(m.check(now: 103), .none, "最初の無応答から window(6s) 経過するまで待つ")
    }

    func test_unanswered_thresholdAndWindow_rotate() {
        let m = monitor(upstreamCount: 2)
        m.recordForward(now: 100)
        m.recordForward(now: 101)
        m.recordForward(now: 102)
        XCTAssertEqual(m.check(now: 106), .rotate)
    }

    func test_response_clearsUnansweredRun() {
        let m = monitor(upstreamCount: 2)
        m.recordForward(now: 100)
        m.recordForward(now: 101)
        m.recordForward(now: 102)
        m.recordResponse(now: 103)
        XCTAssertEqual(m.check(now: 110), .none, "1件でも応答があれば上流は生きている")
    }

    func test_afterRotation_windowRestarts() {
        let m = monitor(upstreamCount: 2)
        m.recordForward(now: 100)
        m.recordForward(now: 101)
        m.recordForward(now: 102)
        XCTAssertEqual(m.check(now: 106), .rotate)
        m.noteRotation(now: 106)
        XCTAssertEqual(m.check(now: 107), .none, "新しい上流には新しい window を与える")
    }

    func test_allUpstreamsExhausted_stopTunnel() {
        let m = monitor(upstreamCount: 2)
        m.recordForward(now: 100); m.recordForward(now: 101); m.recordForward(now: 102)
        XCTAssertEqual(m.check(now: 106), .rotate)
        m.noteRotation(now: 106)
        m.recordForward(now: 107); m.recordForward(now: 108); m.recordForward(now: 109)
        XCTAssertEqual(m.check(now: 113), .stopTunnel, "最後の上流も無応答 → トンネル自動停止で通信を返す")
    }

    func test_response_resetsRotationBudget() {
        let m = monitor(upstreamCount: 2)
        m.recordForward(now: 100); m.recordForward(now: 101); m.recordForward(now: 102)
        XCTAssertEqual(m.check(now: 106), .rotate)
        m.noteRotation(now: 106)
        m.recordResponse(now: 107)   // 2本目の上流は生きている
        m.recordForward(now: 200); m.recordForward(now: 201); m.recordForward(now: 202)
        XCTAssertEqual(m.check(now: 208), .rotate, "応答実績があれば rotation 予算はリセット（即 stop しない）")
    }

    func test_singleUpstream_unresponsive_stopTunnel() {
        let m = monitor(upstreamCount: 1)
        m.recordForward(now: 100); m.recordForward(now: 101); m.recordForward(now: 102)
        XCTAssertEqual(m.check(now: 106), .stopTunnel, "回す先が無ければ即 stop")
    }
}
