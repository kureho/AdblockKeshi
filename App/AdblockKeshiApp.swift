import SwiftUI

@main
struct AdblockKeshiApp: App {
    @State private var selectedTab: AppTab = .blocker
    @State private var reviewCoordinator = ReviewPromptCoordinator.shared
    @StateObject private var appState = AppStateStore()
    @StateObject private var historyStore = LocalReportHistoryStore()
    private let apiClient: ReportAPIClientProtocol = ReportAPIClient(
        baseURL: AppConfig.workersBaseURL,
        uuidStore: DeviceUUIDStore(serverSalt: DeviceUUIDStore.loadServerSaltFromBundle())
    )

    init() {
        BackgroundTaskManager.register()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-report-tab") {
            _selectedTab = State(initialValue: .report)
        }
        #endif
    }

    /// Pro/課金の単一ソース（アプリ全体で共有）。
    @State private var proStore = ProStore()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // UI 検証用ハーネス: DNS 設定画面を直接開く（-FORCE_PRO で Pro 状態も確認可）。
            if ProcessInfo.processInfo.arguments.contains("--show-dns-settings") {
                NavigationStack { DNSSettingsView(store: proStore) }
                    .preferredColorScheme(.light)
            } else {
                mainTabView
            }
            #else
            mainTabView
            #endif
        }
    }

    private var mainTabView: some View {
            TabView(selection: $selectedTab) {
                ContentView()
                    .tabItem {
                        Image(systemName: "shield.checkered")
                        Text("ブロッカー")
                    }
                    .tag(AppTab.blocker)

                ReportTabView(
                    apiClient: apiClient,
                    historyStore: historyStore,
                    onTabReturn: { selectedTab = .blocker }
                )
                .tabItem {
                    Image(systemName: "exclamationmark.bubble")
                    Text("報告")
                }
                .tag(AppTab.report)
            }
            .preferredColorScheme(.light)
            .environmentObject(appState)
            .overlay {
                // 満足度カード (報告送信成功・閾値到達時のみ。頻度制御は ReviewPrompt が担う)
                if reviewCoordinator.showSatisfactionPrompt {
                    SatisfactionPromptView {
                        reviewCoordinator.showSatisfactionPrompt = false
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: reviewCoordinator.showSatisfactionPrompt)
            .task {
                migrateReportedRulesIfNeeded()
                ReviewPrompt.recordFirstLaunchIfNeeded()
                ReviewPrompt.migrateThresholdsIfNeeded()   // 旧閾値の発火済みを新閾値へ（重複プロンプト防止）
                await appState.refresh()
                bumpDailyUsageIfNeeded()
                // DNS リストの鮮度維持（tunnel 未起動でも最新化・Task 14.5）。ネットワークは非ブロッキング。
                Task.detached { await DNSListUpdater.shared()?.updateIfNeeded() }
            }
            .onAppear {
                BackgroundTaskManager.schedule()
            }
    }
}

extension AdblockKeshiApp {
    /// ハッピーモーメント: 「ブロッカーが有効な状態で使った日」を1日1回だけカウント。
    /// 報告送信は行うユーザーが少なく発火機会にならないため、日数ベースに変更（2026-06-11 kureho 判断）。
    /// 表示は起動直後を避けてひと呼吸（2.5秒）置く（起動時即表示は離脱+50%の実証データあり）。
    private func bumpDailyUsageIfNeeded() {
        let snapshot = appState.currentSnapshot
        guard snapshot?.baseEnabled == true else { return }
        let defaults = UserDefaults.standard
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        guard defaults.string(forKey: "reviewPrompt.lastDailyBumpDay") != today else { return }
        defaults.set(today, forKey: "reviewPrompt.lastDailyBumpDay")
        ReviewPrompt.bumpAndMaybeRequest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                ReviewPromptCoordinator.shared.showSatisfactionPrompt = true
            }
        }
    }
}

extension AdblockKeshiApp {
    /// 起動時: ①既存端末治癒（旧版の document 遮断 self-rule を purge）②報告反映(popunder)の
    /// combined を必要時のみ再生成して報告反映 ContentBlocker を reload（基本保護は bundle variant へ戻す）。
    /// 自己学習は「報告反映」拡張に統合（旧 reportedblocker 廃止・名称整合で popunder へ再配置）。
    /// 重い処理は coordinator が off-main で行う（起動フリーズ回避）。
    /// 初回アップデート起動時はここで初めて combined-popunder が生成される。
    private func migrateReportedRulesIfNeeded() {
        if let store = SelfReportedRulesStore() { _ = try? store.sanitizeStoredSelfRules() }
        CombinedRuleListCoordinator.scheduleRegenerate()
    }
}

enum AppTab: Hashable {
    case blocker
    case report
}
