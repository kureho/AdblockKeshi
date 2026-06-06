import SwiftUI

struct ReportHistoryView: View {
    @ObservedObject var viewModel: ReportHistoryViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("読み込み中…").progressViewStyle(.circular)
            case .empty:
                emptyState
            case .error(let msg):
                errorState(message: msg)
            case .cached(let response), .loaded(let response):
                List {
                    Section {
                        ForEach(response.items) { item in
                            ReportHistoryItemView(item: item)
                        }
                    } footer: {
                        Text("最終更新: \(formatFetchedAt(response.fetchedAt))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("報告履歴")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 48)).foregroundStyle(.tertiary)
            Text("まだ報告がありません").font(.headline)
            Text("Tab B トップ画面から、消えない広告を報告してください。")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 48)).foregroundStyle(.orange)
            Text("読み込めませんでした").font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("再試行") { Task { await viewModel.refresh() } }
                .buttonStyle(.bordered)
        }
        .padding(40)
    }

    private func formatFetchedAt(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: date)
    }
}
