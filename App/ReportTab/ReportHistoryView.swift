import SwiftUI

struct ReportHistoryView: View {
    @ObservedObject var store: LocalReportHistoryStore
    let apiClient: ReportAPIClientProtocol

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
        // A-88 §3・進め方4: 履歴を開いたときに serverId のある行だけ結果を取りに行く。
        // 連打・頻繁な再取得は store 側の throttle（既定 10 分）が吸収し、通信失敗も
        // 例外を投げず今の表示のまま保つ（refreshStatuses 内で catch 済み）。
        .task {
            await store.refreshStatuses(apiClient: apiClient)
        }
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
