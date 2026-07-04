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
            .padding(.horizontal, ScreenshotMode.extraHorizontalPadding)
        }
        .task {
            #if DEBUG
            // iOS 26 シミュレータ: --force-enabled 時に CompletedView render と並行で
            // reloadContentBlocker が走ると SFContentBlockerStateChecker の XPC connection が
            // _xpc_api_misuse で EXC_BREAKPOINT。force 系 flag 中は reload をスキップする。
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--force-enabled") || args.contains("--force-error") || args.contains("--force-disabled") {
                return
            }
            #endif
            await downloadAndReload()
        }
        .onAppear(perform: refreshState)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshState()
        }
    }

    private func refreshState() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--force-enabled") {
            // iOS 26: 初期 frame で .enabled に切替えると SFContentBlockerStateChecker と
            // CompletedView render が race で SIGTRAP。最初 .disabled で初期化 → 800ms 後に
            // .enabled に遷移して system 側の state check が安定してから CompletedView を見せる。
            self.blockerState = .disabled
            self.isChecking = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.blockerState = .enabled
            }
            return
        }
        if args.contains("--force-disabled") {
            self.blockerState = .disabled
            self.isChecking = false
            return
        }
        if args.contains("--force-error") {
            self.blockerState = .error("デバッグ用の強制エラー表示")
            self.isChecking = false
            return
        }
        #endif
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

    /// CDN manifest の sha 差分がある variant のみ DL → 検証 → App Group 適用 → reload。
    /// 旧実装の「毎起動 22MB blockerList.json DL（読む者がいない）」は RuleUpdater が廃止・掃除する。
    private func downloadAndReload() async {
        do {
            let identifier = extensionIdentifier
            if let updater = RuleUpdater(reload: { await reloadBasicBlocker(identifier: identifier) }) {
                let outcome = try await updater.updateIfNeeded()
                print("[RuleUpdater] applied=\(outcome.applied) recorded=\(outcome.recordedWithoutDownload) skipped=\(outcome.skipped) failed=\(outcome.failed)")
                if outcome.reloaded {
                    refreshState()
                }
            } else {
                print("[RuleUpdater] App Group container unavailable. Bundle fallback active.")
            }
        } catch {
            print("[RuleUpdater] failed: \(error.localizedDescription). 既存ルールを維持（App Group → bundle fallback）")
        }
        // 報告反映・popunder は独立した CDN ファイルなので、manifest 取得失敗時も best-effort で同期する
        // 報告から配信されたグローバル学習フィルタを取得して自己報告とマージ・reload
        await ReportedGlobalSync.sync()
        // popunder 対策フィルタ(CDN living list)も取得して App Group へ反映・reload（best-effort）
        await PopunderGlobalSync.sync()
    }
}

/// 基本保護 ContentBlocker の reload（完了待ち版）。RuleUpdater の reload closure から使う。
private func reloadBasicBlocker(identifier: String) async {
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        SFContentBlockerManager.reloadContentBlocker(withIdentifier: identifier) { error in
            if let error = error {
                print("[reload] error: \(error.localizedDescription)")
            } else {
                print("[reload] success")
            }
            cont.resume()
        }
    }
}

struct CompletedView: View {
    @State private var pulse = false
    /// moat（報告で追加 N 件）表示用。「フィルタ最終更新」の日付には使わない（虚偽表示解消）。
    @State private var versionInfo: VersionInfo? = nil
    /// 実際に端末へ適用された variant の記録（RuleUpdater が適用成功時に書く）。
    @State private var appliedRecords: [String: AppliedRulesRecord] = [:]
    /// CDN 未取得端末のフォールバック: bundle 同梱ルールの生成日。
    @State private var bundledGeneratedAt: Date? = nil
    @StateObject private var controlVM: BlockerControlViewModel
    private let versionStore: VersionInfoStore

    init(versionStore: VersionInfoStore = VersionInfoStore()) {
        let store = StateStore.sharedAppGroup()
            ?? StateStore(stateFileURL: URL(fileURLWithPath: NSTemporaryDirectory() + "fallback-state.json"))
        _controlVM = StateObject(
            wrappedValue: BlockerControlViewModel(
                store: store,
                reloader: { identifier in
                    SFContentBlockerManager.reloadContentBlocker(withIdentifier: identifier) { error in
                        if let error = error {
                            print("[reload] error: \(error.localizedDescription)")
                        }
                    }
                }
            )
        )
        self.versionStore = versionStore
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                // Hero check icon with subtle pulse
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulse ? 1.08 : 1.0)
                        .opacity(pulse ? 0.6 : 1.0)

                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 120, height: 120)

                    Image(systemName: "checkmark.shield.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.7)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
                .onAppear {
                    // iOS 26 + ScrollView 内で `.repeatForever` 直起動が NSISEngine の API Misuse
                    // (EXC_BREAKPOINT) を引き起こすため、次 runloop に逃して 1 回 layout が安定してから開始する
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                }

                VStack(spacing: 8) {
                    Text("広告ブロック中")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("Safari の広告は表示されません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // v2.0: 2 トグル UI (広告 / セキュリティ)
                BlockerControlView(viewModel: controlVM)

                VStack(alignment: .leading, spacing: 10) {
                    InfoRow(
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: .accentColor,
                        text: filterUpdateText
                    )
                    if let moatText = versionInfo?.moatDisplayText {
                        InfoRow(
                            icon: "person.2.fill",
                            iconColor: .blue,
                            text: moatText
                        )
                    }
                    InfoRow(
                        icon: "moon.zzz.fill",
                        iconColor: .purple,
                        text: "設定は一度だけ。あとはお任せください"
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .padding(.horizontal, 20)

                Spacer(minLength: 20)

                NavigationLink("このアプリについて") {
                    AboutView()
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(UIColor.systemBackground),
                    Color.green.opacity(0.04)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        // iOS 26: NavigationStack の中に navigationTitle 未設定の View が来ると
        // NavigationBar 配置時に NSISEngine が API Misuse で SIGTRAP (EXC_BREAKPOINT)。
        // CompletedView は title を持たないので NavigationBar を明示的に非表示にする。
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            versionInfo = versionStore.read()
            appliedRecords = AppliedRulesStore()?.read() ?? [:]
            bundledGeneratedAt = BundledRulesInfo.generatedAt()
        }
    }

    /// フィルタ更新状況の表示テキスト。
    /// 表示日付 = 現在の state で拡張が実際に読む variant の適用記録（generated_at）。
    /// 適用記録が無い端末（CDN 未取得）は bundle 同梱ルールの生成日（虚偽表示の解消）。
    private var filterUpdateText: String {
        let state = BlockerTogglesState(
            adEnabled: controlVM.adEnabled,
            securityEnabled: controlVM.securityEnabled
        )
        guard let date = FilterUpdateDisplay.displayDate(
            state: state,
            applied: appliedRecords,
            bundledGeneratedAt: bundledGeneratedAt
        ) else {
            return "フィルタは自動で最新の状態に保たれます"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return "フィルタ最終更新: \(formatter.string(from: date))"
    }
}

struct InfoRow: View {
    let icon: String
    let iconColor: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 24)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
            }
            VStack(spacing: 8) {
                Text("確認できませんでした")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            Button("もう一度試す", action: onRetry)
                .font(.system(.body, weight: .semibold))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
                .foregroundColor(.accentColor)
            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
