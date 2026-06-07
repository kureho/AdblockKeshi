import SwiftUI

struct OnboardingView: View {
    let onReady: () -> Void

    @State private var showFilterInfo = false

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
                            Text("2 つのフィルタを両方 ON")
                                .font(.system(.callout, weight: .semibold))

                            // 2 フィルタ inline 列挙 (アイコン + 名前)
                            VStack(alignment: .leading, spacing: 6) {
                                FilterInlineRow(iconName: "shield.fill", name: "標準フィルタ")
                                FilterInlineRow(iconName: "sparkles", name: "自己学習フィルタ")
                            }

                            // グレー補足文
                            Text("両方 ON で広告ブロックが完全に有効になります")
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
                        title: "標準フィルタ",
                        detail: "15 万件の広告・詐欺サイトを基本ブロック。EasyList・AdGuard 等の公式リストを採用。"
                    )

                    FilterDescriptionCard(
                        iconName: "sparkles",
                        title: "自己学習フィルタ",
                        detail: "他のブロッカーで消えない広告を、ユーザーからの報告で自動で取り込んで進化していきます。"
                    )

                    Text("両方を ON にすると、基本ブロック + 進化するフィルタで、より強力に広告を消せます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationTitle("2 つのフィルタについて")
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
