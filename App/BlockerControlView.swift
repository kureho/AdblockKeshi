import Combine
import SwiftUI
import SafariServices

/// v2.0 で追加。広告 / セキュリティ 2 トグルの ViewModel。
/// トグル変更は 500ms debounce で state.json 書込 + 基本保護の reload 1 回 → 完了後に 2 本目の作り直し。
@MainActor
final class BlockerControlViewModel: ObservableObject {
    @Published var adEnabled: Bool
    @Published var securityEnabled: Bool

    private let store: StateStore
    private let markPending: @MainActor (String) -> Void
    private let reloader: @MainActor (String) async -> Void
    private let regenerate: () -> Void
    private let blockerIdentifier: String
    private var cancellables = Set<AnyCancellable>()

    init(
        store: StateStore,
        markPending: @escaping @MainActor (String) -> Void,
        reloader: @escaping @MainActor (String) async -> Void,
        regenerate: @escaping () -> Void = BlockerControlViewModel.regenerateInBackgroundTask,
        blockerIdentifier: String = "com.kureho.adblockkeshi.blocker"
    ) {
        self.store = store
        self.markPending = markPending
        self.reloader = reloader
        self.regenerate = regenerate
        self.blockerIdentifier = blockerIdentifier
        let initial = store.read()
        self.adEnabled = initial.adEnabled
        self.securityEnabled = initial.securityEnabled

        // 連打対策: 500ms debounce で reload を 1 回に統合
        Publishers.CombineLatest($adEnabled, $securityEnabled)
            .dropFirst()  // 初期化時の値は無視
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] ad, sec in
                self?.persistAndReload(adEnabled: ad, securityEnabled: sec)
            }
            .store(in: &cancellables)
    }

    private func persistAndReload(adEnabled: Bool, securityEnabled: Bool) {
        let state = BlockerTogglesState(
            adEnabled: adEnabled,
            securityEnabled: securityEnabled,
            updatedAt: Date()
        )
        let identifier = blockerIdentifier
        // ★保存より前に「読み込みが要る」印を付ける。保存の直後〜読み込みの依頼までにアプリが終了しても、
        // 次の起動で読み込み直せる（保存は ON・Safari は OFF のまま治らなかった 2026-10-03 の不具合）。
        markPending(identifier)
        try? store.write(state)
        Task {
            // 基本保護(.blocker)を新 state で reload（bundle variant を読む）。
            await reloader(identifier)
            // 報告反映(popunder)の combined を必要時のみ再生成（off-main・change-guard）。
            // ★基本保護のコンパイル（約 11 万件）が終わってから＝重い処理を同時に走らせない
            // （CDN 更新時の「基本保護へ適用 → 2 本目を作り直す」と同じ順番）。
            regenerate()
        }
    }

    /// トグル直後に Safari へ移られても 2 本目の作り直し（数秒）が止められないよう、実行延長を取って作り直す。
    static func regenerateInBackgroundTask() {
        let endBackground = ContentBlockerReloader.beginBackgroundTask()
        CombinedRuleListCoordinator.scheduleRegenerate {
            Task { @MainActor in endBackground() }
        }
    }
}

/// v2.0 で追加。メイン画面に統合する 2 トグル UI。
struct BlockerControlView: View {
    @ObservedObject var viewModel: BlockerControlViewModel

    var body: some View {
        VStack(spacing: 12) {
            BlockerToggleRow(
                label: "広告ブロック",
                icon: "shield.fill",
                iconColor: .green,
                isOn: $viewModel.adEnabled
            )
            BlockerToggleRow(
                label: "詐欺サイトブロック",
                icon: "exclamationmark.shield.fill",
                iconColor: .orange,
                isOn: $viewModel.securityEnabled
            )
        }
        .padding(.horizontal, 20)
    }
}

private struct BlockerToggleRow: View {
    let label: String
    let icon: String
    let iconColor: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            Text(label)
                .font(.system(.body, weight: .medium))
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

private struct BlockerControlPreviewWrapper: View {
    @StateObject private var vm: BlockerControlViewModel

    init() {
        let store = StateStore(
            stateFileURL: URL(fileURLWithPath: NSTemporaryDirectory() + "preview-state.json")
        )
        _vm = StateObject(wrappedValue: BlockerControlViewModel(store: store, markPending: { _ in }, reloader: { _ in }))
    }

    var body: some View {
        BlockerControlView(viewModel: vm)
            .padding()
    }
}

#Preview {
    BlockerControlPreviewWrapper()
}
