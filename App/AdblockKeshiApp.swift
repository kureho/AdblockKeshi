import SwiftUI

@main
struct AdblockKeshiApp: App {
    init() {
        BackgroundTaskManager.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    BackgroundTaskManager.schedule()
                }
        }
    }
}
