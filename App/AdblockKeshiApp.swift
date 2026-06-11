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
                ReviewPrompt.recordFirstLaunchIfNeeded()
                await appState.refresh()
            }
            .onAppear {
                BackgroundTaskManager.schedule()
            }
        }
    }
}

enum AppTab: Hashable {
    case blocker
    case report
}
