import SwiftUI

@main
struct AdblockKeshiApp: App {
    @State private var selectedTab: AppTab = .blocker
    private let apiClient: ReportAPIClientProtocol = StubReportAPIClient()

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
