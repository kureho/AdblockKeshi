import Foundation

/// 診断情報の実機での取得元。**どれも失敗したら nil を返すだけ**（throw も表示もしない）。
enum ReportDiagnosticsSources {

    /// system API の応答を待つ上限。これを過ぎたら診断を諦めて報告を送る。
    static let timeout: TimeInterval = 3

    /// Safari Content Blocker が有効か。設定アプリのトグルは非同期でしか読めない。
    static let blockerEnabled: @Sendable () async -> Bool? = {
        await BestEffortValue.resolve(timeout: timeout) { done in
            ContentBlockerStateChecker().fetchState { state in
                switch state {
                case .enabled:  done(true)
                case .disabled: done(false)
                case .error:    done(nil)   // 取れなかった ≠ 無効。誤診断を避けて NULL にする
                }
            }
        }
    }

    /// DNS 保護が実際に動いていたか。購入状態ではなく tunnel の実状態を見る。
    static let dnsEnabled: @Sendable () async -> Bool? = {
        await BestEffortValue.resolve(timeout: timeout) { done in
            Task { done(await TunnelManager.currentlyProtecting()) }
        }
    }

    static let appVersion: @Sendable () -> String? = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static let appBuild: @Sendable () -> String? = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    /// 端末が実際に読んでいるフィルタの生成日。UI の「フィルタ最終更新」と同じ値。
    static let filterVersion: @Sendable () -> String? = {
        let state = StateStore.sharedAppGroup()?.read() ?? .default
        let applied = AppliedRulesStore()?.read() ?? [:]
        let date = FilterUpdateDisplay.displayDate(
            state: state,
            applied: applied,
            bundledGeneratedAt: BundledRulesInfo.generatedAt()
        )
        return ReportFilterVersion.format(date)
    }
}
