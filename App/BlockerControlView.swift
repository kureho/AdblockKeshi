import Combine
import SwiftUI
import SafariServices

/// v2.0 で追加。広告 / セキュリティ 2 トグルの ViewModel。
/// トグル変更は 500ms debounce で state.json 書込 + reloadContentBlocker 1 回。
@MainActor
final class BlockerControlViewModel: ObservableObject {
    @Published var adEnabled: Bool
    @Published var securityEnabled: Bool

    private let store: StateStore
    private let reloader: (String) -> Void
    private let blockerIdentifier: String
    private var cancellables = Set<AnyCancellable>()

    init(
        store: StateStore,
        reloader: @escaping (String) -> Void,
        blockerIdentifier: String = "com.kureho.adblockkeshi.blocker"
    ) {
        self.store = store
        self.reloader = reloader
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
        try? store.write(state)
        reloader(blockerIdentifier)   // 基本保護(.blocker)を新 state で reload（bundle variant を読む）
        // 報告反映(popunder)の combined を必要時のみ再生成（off-main・change-guard）。
        // トグル自体は基本保護の variant 切替なので reloader が担い、coordinator は報告反映側を保つ。
        CombinedRuleListCoordinator.scheduleRegenerate()
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
        _vm = StateObject(wrappedValue: BlockerControlViewModel(store: store, reloader: { _ in }))
    }

    var body: some View {
        BlockerControlView(viewModel: vm)
            .padding()
    }
}

#Preview {
    BlockerControlPreviewWrapper()
}
