import SwiftUI
import SafariServices

struct ContentView: View {
    @State private var blockerState: BlockerState = .disabled
    @State private var isChecking: Bool = false

    private let checker = ContentBlockerStateChecker()
    private let extensionIdentifier = "com.kureho.adblockkeshi.blocker"

    var body: some View {
        NavigationStack {
            Group {
                switch blockerState {
                case .enabled:
                    CompletedView()
                case .disabled:
                    OnboardingView(onReady: openAppSettings)
                case .error(let message):
                    ErrorView(message: message, onRetry: refreshState)
                }
            }
            .overlay {
                if isChecking {
                    ProgressView()
                        .controlSize(.regular)
                }
            }
        }
        .task {
            await downloadAndReload()
        }
        .onAppear(perform: refreshState)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshState()
        }
    }

    private func refreshState() {
        isChecking = true
        checker.fetchState { state in
            DispatchQueue.main.async {
                self.blockerState = state
                self.isChecking = false
            }
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func downloadAndReload() async {
        do {
            let downloader = FilterDownloader()
            let bytes = try await downloader.downloadAndStore()
            print("[FilterDownloader] downloaded \(bytes) bytes")
            SFContentBlockerManager.reloadContentBlocker(
                withIdentifier: extensionIdentifier
            ) { error in
                if let error = error {
                    print("[reload] error: \(error.localizedDescription)")
                } else {
                    print("[reload] success")
                    refreshState()
                }
            }
        } catch {
            print("[FilterDownloader] failed: \(error.localizedDescription). Bundle fallback active.")
        }
    }
}

struct CompletedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 100, height: 100)
                .foregroundColor(.green)
            Text("広告ブロック中")
                .font(.largeTitle)
                .bold()
            Text("もうこのアプリを開く必要はありません")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Safariを開く") {
                if let url = URL(string: "https://www.apple.com/jp/safari/") {
                    UIApplication.shared.open(url)
                }
            }
            .padding(.top, 24)

            Spacer()

            NavigationLink("このアプリについて") {
                AboutView()
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.bottom)
        }
        .padding()
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.orange)
            Text("確認できませんでした")
                .font(.title2)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("もう一度試す", action: onRetry)
                .padding(.top, 16)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
