import Foundation

/// watchdog フェイルセーフの判定機（4.0.1 hotfix）。
/// 「転送はしているのに上流応答がゼロ」が window 秒続いたら rotate、全上流を使い切ったら stopTunnel。
/// v4.0.0 のモバイル回線全断（上流不達のままトンネルが DNS を握り続ける）を構造的に不可能にする。
/// 時刻は引数注入の純ロジック。呼び出しは Provider の workQueue 上に直列化される前提（内部ロック無し）。
final class DNSHealthMonitor {

    enum Action: Equatable {
        case none
        case rotate       // 次の上流に切り替える
        case stopTunnel   // 全上流が無応答 → トンネルを止めて素の通信に戻す
    }

    private let minUnansweredQueries: Int
    private let window: TimeInterval
    private let upstreamCount: Int

    private var unansweredCount = 0
    private var firstUnansweredAt: TimeInterval?
    private var rotations = 0

    init(minUnansweredQueries: Int = 3, window: TimeInterval = 6, upstreamCount: Int) {
        self.minUnansweredQueries = minUnansweredQueries
        self.window = window
        self.upstreamCount = upstreamCount
    }

    func recordForward(now: TimeInterval) {
        unansweredCount += 1
        if firstUnansweredAt == nil { firstUnansweredAt = now }
    }

    func recordResponse(now: TimeInterval) {
        unansweredCount = 0
        firstUnansweredAt = nil
        rotations = 0   // 応答実績のある上流に切り替わった → rotation 予算を回復
    }

    /// サスペンド復帰・電波喪失など「無応答が上流劣化の証拠にならない」区間があった時の白紙化。
    /// window も rotation 予算も戻す（停止中に溜まった記録で誤 rotate / 誤 stopTunnel しない）。
    func reset() {
        unansweredCount = 0
        firstUnansweredAt = nil
        rotations = 0
    }

    func noteRotation(now: TimeInterval) {
        rotations += 1
        unansweredCount = 0
        firstUnansweredAt = nil   // 新しい上流には新しい window
    }

    func check(now: TimeInterval) -> Action {
        guard unansweredCount >= minUnansweredQueries,
              let t0 = firstUnansweredAt, now - t0 >= window else { return .none }
        return rotations < upstreamCount - 1 ? .rotate : .stopTunnel
    }
}
