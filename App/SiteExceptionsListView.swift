import SwiftUI

/// 「ブロック停止中のサイト」の管理リスト（v4.2.0）。
/// per-site 例外は壊れ報告フローからのみ追加される（ここでは削除だけ）。
/// 削除 = そのサイトでブロックを再開する。変更のたびに combined を再生成して即反映。
struct SiteExceptionsListView: View {
    /// 変更（削除）があったときに親へ知らせる（件数バッジの更新用）。
    let onChange: () -> Void

    @State private var domains: [String] = []

    var body: some View {
        List {
            Section {
                ForEach(domains, id: \.self) { domain in
                    HStack {
                        Text(domain)
                            .font(.callout)
                        Spacer()
                        Button("再開") {
                            remove(domain)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        remove(domains[offset])
                    }
                }
            } footer: {
                Text("これらのサイトでは広告ブロックを停止しています（表示崩れ対策）。「再開」でブロックが元に戻ります。")
                    .font(.caption2)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("ブロック停止中のサイト")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { domains = SiteExceptionsStore.sharedAppGroup()?.readDomains() ?? [] }
        .overlay {
            if domains.isEmpty {
                ContentUnavailableView(
                    "停止中のサイトはありません",
                    systemImage: "checkmark.shield",
                    description: Text("すべてのサイトでブロックが有効です")
                )
            }
        }
    }

    private func remove(_ domain: String) {
        guard let store = SiteExceptionsStore.sharedAppGroup() else { return }
        try? store.remove(domain)
        domains = store.readDomains()
        CombinedRuleListCoordinator.scheduleRegenerate()
        onChange()
    }
}
