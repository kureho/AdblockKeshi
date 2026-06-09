import SwiftUI

struct ReportHistoryView: View {
    @ObservedObject var store: LocalReportHistoryStore

    var body: some View {
        Group {
            if store.items.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(store.items) { item in
                            ReportHistoryItemView(item: item)
                        }
                        .onDelete { offsets in
                            store.delete(at: offsets)
                        }
                    } footer: {
                        Text("履歴を削除しても、送信済みの報告は取り消されません。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("報告履歴")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 48)).foregroundStyle(.tertiary)
            Text("まだ報告がありません").font(.headline)
            Text("報告タブのトップから、消えない広告を報告してください。")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
