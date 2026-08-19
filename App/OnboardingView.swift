import SwiftUI

struct OnboardingView: View {
    let onReady: () -> Void

    @State private var showFilterInfo: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--show-filter-sheet")
        #else
        return false
        #endif
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Header: Icon + Name
                VStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .padding(.top, 40)

                    Text("広告消し")
                        .font(.system(.title, design: .rounded, weight: .bold))

                    Text("Safari の広告を、シンプルに消す。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Steps
                VStack(spacing: 14) {
                    StepRow(
                        number: 1,
                        title: "下のボタンをタップ",
                        detail: "iOS の設定アプリが開きます"
                    )
                    StepRow(
                        number: 2,
                        title: "Safari → 機能拡張",
                        detail: "設定の中で順番に開きます"
                    )

                    // Step 3: タイトル + 2 フィルタ inline 列挙 + リンク
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Text("3")
                                .font(.system(.callout, design: .rounded, weight: .bold))
                                .foregroundColor(.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("3 つの保護を ON（すべて推奨）")
                                .font(.system(.callout, weight: .semibold))

                            // 3 つの保護 inline 列挙 (アイコン + 名前)
                            VStack(alignment: .leading, spacing: 6) {
                                FilterInlineRow(iconName: "shield.fill", name: "基本保護")
                                FilterInlineRow(iconName: "exclamationmark.bubble.fill", name: "報告反映")
                                FilterInlineRow(iconName: "hand.raised.fill", name: "遷移保護")
                            }

                            // グレー補足文
                            Text("基本保護で一般的な広告・トラッカーを防ぎ、報告反映で検証済みの追加対策を反映、遷移保護で勝手に開くタブや広告ページへの移動を防ぎます")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)

                            // リンク
                            Button {
                                showFilterInfo = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.caption)
                                    Text("フィルタの種類について")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(
                                    Capsule().fill(Color.accentColor.opacity(0.10))
                                )
                            }
                            .padding(.top, 2)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(UIColor.secondarySystemBackground))
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Spacer(minLength: 20)

                // CTA
                VStack(spacing: 12) {
                    Button(action: onReady) {
                        HStack(spacing: 8) {
                            Text("準備する")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 12, x: 0, y: 6)
                    }

                    Text("一度だけ ON にすれば、もう開く必要はありません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)

                NavigationLink("ライセンス情報") {
                    AboutView()
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showFilterInfo) {
            FilterInfoSheet()
                .presentationDetents([.medium])
        }
        .background(
            LinearGradient(
                colors: [
                    Color(UIColor.systemBackground),
                    Color.accentColor.opacity(0.04)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Step 3 内の 2 フィルタ inline 行

struct FilterInlineRow: View {
    let iconName: String
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 24, height: 24)
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(name)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - 詳細 Sheet

struct FilterInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FilterDescriptionCard(
                        iconName: "shield.fill",
                        title: "基本保護",
                        detail: "一般的な広告やトラッカーを、安定したルールでブロックします（EasyList・AdGuard 等の公式リスト採用）。他のブロッカーで消えない広告は、利用者からの報告を参考にフィルタを改善しています。"
                    )

                    FilterDescriptionCard(
                        iconName: "exclamationmark.bubble.fill",
                        title: "報告反映",
                        detail: "利用者から届いた広告報告をもとに、安全性を確認した追加対策を反映します。動画・まとめサイト等でサムネをタップすると広告サイトに飛ばされる「タップ乗っ取り」も、既知の広告ネットワークのスクリプトをブロックして抑えます。"
                    )

                    FilterDescriptionCard(
                        iconName: "hand.raised.fill",
                        title: "遷移保護",
                        detail: "勝手に開くタブや、広告ページへの意図しない移動を防ぎます。サイト自身のスクリプトが開くタブ乗っ取りを、対象サイトに限って止めます。"
                    )

                    StrongModePermissionNote()

                    Text("基本保護・報告反映・遷移保護の3つすべてを ON にすると、もっとも広告を防げます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationTitle("フィルタについて")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

struct FilterDescriptionCard: View {
    let iconName: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.callout, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text("\(number)")
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.callout, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

#Preview {
    NavigationStack {
        OnboardingView(onReady: {})
    }
}
