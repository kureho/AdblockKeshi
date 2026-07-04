import BackgroundTasks
import SafariServices

enum BackgroundTaskManager {
    static let identifier = "com.kureho.adblockkeshi.filter-refresh"
    static let extensionIdentifier = "com.kureho.adblockkeshi.blocker"
    static let interval: TimeInterval = 7 * 24 * 60 * 60  // 7日

    /// AppDelegate 初期化時に1度だけ呼ぶ。BGTaskScheduler に identifier を登録。
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// 次回のバックグラウンド実行を予約。
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BGTaskScheduler] scheduled for \(request.earliestBeginDate?.description ?? "?")")
        } catch {
            print("[BGTaskScheduler] schedule failed: \(error.localizedDescription)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // 次回分を即予約（仕様: handler 内で必ず再予約）
        schedule()

        let work = Task {
            do {
                // CDN manifest の sha 差分がある variant のみ DL → 検証 → App Group 適用 → reload。
                // 旧実装の「週次 22MB blockerList.json DL（読む者がいない）」は RuleUpdater が廃止・掃除する。
                guard let updater = RuleUpdater(reload: {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        SFContentBlockerManager.reloadContentBlocker(
                            withIdentifier: extensionIdentifier
                        ) { _ in
                            cont.resume()
                        }
                    }
                }) else {
                    print("[BGTask] App Group container unavailable")
                    task.setTaskCompleted(success: false)
                    return
                }
                let outcome = try await updater.updateIfNeeded()
                print("[BGTask] rule update applied=\(outcome.applied) skipped=\(outcome.skipped.count) failed=\(outcome.failed)")
                // 報告から配信されたグローバル学習フィルタも取得して自己報告とマージ・reload
                await ReportedGlobalSync.sync()
                // popunder 対策フィルタ(CDN living list)も取得して App Group へ反映・reload（best-effort）
                await PopunderGlobalSync.sync()
                task.setTaskCompleted(success: outcome.failed.isEmpty)
            } catch {
                print("[BGTask] failed: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            work.cancel()
        }
    }
}
