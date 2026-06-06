import SwiftUI

@main
struct AdblockKeshiApp: App {
    @State private var selectedTab: AppTab = .blocker
    private let stubClient = StubReportAPIClient()
    private var apiClient: ReportAPIClientProtocol { stubClient }
    private var historyFetcher: ReportHistoryFetcher { stubClient }

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
                    historyFetcher: historyFetcher,
                    onTabReturn: { selectedTab = .blocker }
                )
                .tabItem {
                    Image(systemName: "exclamationmark.bubble")
                    Text("報告")
                }
                .tag(AppTab.report)
            }
            .preferredColorScheme(.light)
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
