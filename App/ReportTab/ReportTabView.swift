import SwiftUI

enum ReportTabRoute: Hashable {
    case form
    /// 送信完了。種別・どこで見たか・host で文言と一時オフ提示を出し分けるため一緒に運ぶ。
    case sent(ReportSuccess)
    case history
}

struct ReportTabView: View {
    let apiClient: ReportAPIClientProtocol
    @ObservedObject var historyStore: LocalReportHistoryStore
    let onTabReturn: () -> Void

    @State private var path: [ReportTabRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ReportEntryView(
                onReportTap: { path.append(.form) },
                onHistoryTap: { path.append(.history) }
            )
            .navigationTitle("報告")
            .navigationBarTitleDisplayMode(.inline)
            // `report` のリンクが届いたら、押し込んだ見るだけの画面（報告履歴・送信完了）を根元まで戻して報告タブの根を見せる。
            // 報告フォーム（書きかけの入力）が一番上に出ている時は戻さない（打った URL を消さない・D-150）。
            .onReceive(NotificationCenter.default.publisher(for: DeepLink.didArrive)) { notification in
                guard DeepLink.destinationTab(of: notification) == .report else { return }
                if path.last != .form { path.removeAll() }
            }
            .navigationDestination(for: ReportTabRoute.self) { route in
                switch route {
                case .form:
                    ReportFormView(
                        apiClient: apiClient,
                        historyStore: historyStore,
                        onSubmitSuccess: { success in
                            path.append(.sent(success))
                        }
                    )
                case .sent(let success):
                    ReportSentView(
                        success: success,
                        onAgainTap: {
                            path.removeAll()
                            path.append(.form)
                        },
                        onCloseTap: {
                            path.removeAll()
                            onTabReturn()
                        }
                    )
                case .history:
                    ReportHistoryView(store: historyStore, apiClient: apiClient)
                }
            }
        }
    }
}
