import Foundation

/// completion ベース／非同期の取得を「必ず 1 回だけ・上限時間内に」解決するヘルパー。
///
/// 診断情報の取得元（`SFContentBlockerManager.getStateOfContentBlocker` /
/// `NETunnelProviderManager.loadAllFromPreferences`）はどちらも system API で、
/// 応答が返らない可能性がある。**報告送信をそこで止めてはいけない**ので、
/// 期限が来たら `nil` を返して先へ進む。
///
/// 期限切れ後に本来の completion が来ても無視する。`withCheckedContinuation` を
/// 二重に resume するとクラッシュするため、once ガードは必須。
enum BestEffortValue {

    /// - Parameters:
    ///   - timeout: これを過ぎたら諦めて `nil` を返す。
    ///   - work: 結果（取れなければ `nil`）を completion へ渡す処理。
    static func resolve<T: Sendable>(
        timeout: TimeInterval,
        _ work: @escaping (@escaping @Sendable (T?) -> Void) -> Void
    ) async -> T? {
        let gate = OnceGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                if gate.enter() { continuation.resume(returning: nil) }
            }
            work { value in
                if gate.enter() { continuation.resume(returning: value) }
            }
        }
    }
}

/// 最初の 1 回だけ true を返すスレッドセーフなゲート。
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func enter() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
