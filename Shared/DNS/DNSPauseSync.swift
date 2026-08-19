import Foundation

/// 一時停止状態の同期判定（純ロジック・時刻は引数注入）。
///
/// アプリ → extension の reload 通知（`sendProviderMessage`）は best-effort で、
/// トンネルの状態次第・OS 都合で落ちる。落ちたままだと「アプリでは停止中と表示されているのに
/// DNS はブロックし続ける」「解除したのに素通しのまま」が起きるので、maintenance tick が
/// App Group の実体（`DNSPauseStore`）と自分が握っている期限を毎回突き合わせて取りこぼしを回収する。
enum DNSPauseSync {
    enum Action: Equatable {
        /// 実体と一致している。何もしない。
        case none
        /// 期限切れ → ファイルを片付けて通常運転へ戻す。
        case resumeExpired
        /// 実体と状態がずれている → engine を組み直して実体に合わせる。
        case reload
    }

    /// - Parameters:
    ///   - current: extension が今握っている停止期限（素通し運転中のみ非 nil）
    ///   - stored: `DNSPauseStore.readPausedUntil(now:)` の結果（期限切れ・不正はすでに nil）
    static func decide(current: Date?, stored: Date?, now: Date) -> Action {
        // 期限切れは「ずれ」ではなく自動再開。ファイルの片付けまで走らせる必要があるので先に見る。
        // 境界（now == 期限）は再開側＝保護が生きる方向に倒す。
        if let current, now >= current { return .resumeExpired }
        // 実体（App Group）と握っている期限が食い違う = reload 通知の取りこぼし。
        return current == stored ? .none : .reload
    }
}
