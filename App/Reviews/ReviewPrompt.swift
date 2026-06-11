import Foundation
import StoreKit
import SwiftUI
import UIKit

/// アプリ内レビュー要求の発火を管理する共通ヘルパー (v2)。
/// 仕様: MannerCamera4K/docs/superpowers/specs/2026-06-11-review-prompt-v2-design.md (横展開元)
///
/// 使い方:
/// 1. App.swift の起動時に `ReviewPrompt.recordFirstLaunchIfNeeded()` を呼ぶ
/// 2. 主要操作の成功直後に `ReviewPrompt.bumpAndMaybeRequest(blocked:)` を呼ぶ
///    - `blocked` には「直後に広告等の割り込み UI が出る状態」を渡す（true なら発火を次回に持ち越す）
/// 3. 保存エラー等のネガティブ体験直後に `ReviewPrompt.recordNegativeEvent()` を呼ぶ（7日間発火抑止）
///
/// Apple ガイドライン:
/// - `AppStore.requestReview(in:)` は OS 側で年3回まで自動制御（呼んでも表示しないことがある）
/// - 表示されたか・評価されたかは検知不可のため「発火を要求した日」をクールダウン基準にする
@MainActor
enum ReviewPrompt {
    /// 累計成功回数の発火閾値。5 の倍数を避けて広告サイクル (5枚ごと) との衝突確率を下げる。
    /// 衝突回避の保証は `blocked` 引数 + 持ち越しが担う。
    static let thresholds = [7, 23, 58]

    private static let minimumDaysSinceFirstLaunch = 3
    private static let cooldownDays = 90
    private static let negativeSuppressionDays = 7

    private static let kSuccess = "reviewPrompt.successCount"
    private static let kLast = "reviewPrompt.lastRequestDate"
    private static let kFirst = "reviewPrompt.firstLaunchDate"
    private static let kRequested = "reviewPrompt.requestedCount"
    private static let kFired = "reviewPrompt.firedThresholds"
    private static let kNegative = "reviewPrompt.lastNegativeDate"

    static func recordFirstLaunchIfNeeded(defaults: UserDefaults = .standard, now: Date = Date()) {
        if defaults.object(forKey: kFirst) == nil {
            defaults.set(now, forKey: kFirst)
        }
    }

    /// 保存エラー等のネガティブ体験を記録。以後 7 日間は発火しない。
    static func recordNegativeEvent(defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(now, forKey: kNegative)
    }

    /// 主要操作成功時に呼ぶ。条件を満たせばレビュー要求を発火。
    /// 条件を満たさない場合は機会を消費せず、次回の bump に持ち越す（閾値跨ぎ方式）。
    /// - Parameters:
    ///   - blocked: 直後に広告等の割り込み UI が出る状態なら true（発火を持ち越す）
    ///   - request: テスト用フック。nil なら `AppStore.requestReview(in:)` を呼ぶ
    static func bumpAndMaybeRequest(
        blocked: Bool = false,
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        request: (() -> Void)? = nil
    ) {
        let count = defaults.integer(forKey: kSuccess) + 1
        defaults.set(count, forKey: kSuccess)

        guard let first = defaults.object(forKey: kFirst) as? Date,
              days(from: first, to: now) >= minimumDaysSinceFirstLaunch else { return }

        if let negative = defaults.object(forKey: kNegative) as? Date,
           days(from: negative, to: now) < negativeSuppressionDays { return }

        if let last = defaults.object(forKey: kLast) as? Date,
           days(from: last, to: now) < cooldownDays { return }

        guard !blocked else { return }

        let fired = Set(defaults.array(forKey: kFired) as? [Int] ?? [])
        let pending = thresholds.filter { $0 <= count && !fired.contains($0) }
        guard !pending.isEmpty else { return }

        if let request {
            request()
        } else {
            requestSystemReview()
        }
        defaults.set(now, forKey: kLast)
        defaults.set(defaults.integer(forKey: kRequested) + 1, forKey: kRequested)
        defaults.set(fired.union(pending).sorted(), forKey: kFired)
    }

    private static func requestSystemReview() {
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        {
            AppStore.requestReview(in: scene)
        }
    }

    /// テスト用: 全状態をリセット（リリースビルドでは呼ばないこと）
    static func resetForDebug(defaults: UserDefaults = .standard) {
        for key in [kSuccess, kLast, kFirst, kRequested, kFired, kNegative] {
            defaults.removeObject(forKey: key)
        }
    }

    private static func days(from: Date, to: Date) -> Int {
        Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
