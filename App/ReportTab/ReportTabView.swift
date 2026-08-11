import SwiftUI

enum ReportTabRoute: Hashable {
    case form
    /// 送信完了。どこで見た広告かで文言を出し分けるため一緒に運ぶ。
    case sent(SeenIn)
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
            .navigationDestination(for: ReportTabRoute.self) { route in
                switch route {
                case .form:
                    ReportFormView(
                        apiClient: apiClient,
                        historyStore: historyStore,
                        onSubmitSuccess: { seenIn in
                            path.append(.sent(seenIn))
                        }
                    )
                case .sent(let seenIn):
                    ReportSentView(
                        seenIn: seenIn,
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
                    ReportHistoryView(store: historyStore)
                }
            }
        }
    }
}
