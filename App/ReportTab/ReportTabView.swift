import SwiftUI

enum ReportTabRoute: Hashable {
    case form
    case sent
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
                        onSubmitSuccess: {
                            path.append(.sent)
                        }
                    )
                case .sent:
                    ReportSentView(
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
