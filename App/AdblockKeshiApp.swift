import SwiftUI
import SafariServices

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

    var body: some Scene {
        WindowGroup {
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
                await appState.refresh()
                bumpDailyUsageIfNeeded()
            }
            .onAppear {
                BackgroundTaskManager.schedule()
            }
        }
    }
}

extension AdblockKeshiApp {
    /// ハッピーモーメント: 「ブロッカーが有効な状態で使った日」を1日1回だけカウント。
    /// 報告送信は行うユーザーが少なく発火機会にならないため、日数ベースに変更（2026-06-11 kureho 判断）。
    /// 表示は起動直後を避けてひと呼吸（2.5秒）置く（起動時即表示は離脱+50%の実証データあり）。
    private func bumpDailyUsageIfNeeded() {
        let snapshot = appState.currentSnapshot
        guard snapshot?.baseEnabled == true || snapshot?.reportedEnabled == true else { return }
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
    /// 既存端末治癒（2026-06-23）: 旧版で生成された「document を遮断し得る自己報告ルール」を
    /// 起動時に purge する。ネットワーク非依存・idempotent。除去が発生したときだけ報告
    /// Content Blocker を reload して即座に反映する（被害端末がアップデートしただけで治る）。
    private func migrateReportedRulesIfNeeded() {
        guard let store = SelfReportedRulesStore() else { return }
        guard (try? store.sanitizeStoredSelfRules()) == true else { return }
        SFContentBlockerManager.reloadContentBlocker(
            withIdentifier: SFContentBlockerStateChecker.reportedID
        ) { _ in }
    }
}

enum AppTab: Hashable {
    case blocker
    case report
}
