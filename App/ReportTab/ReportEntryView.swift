import SwiftUI

struct ReportEntryView: View {
    let onReportTap: () -> Void
    let onHistoryTap: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                primaryCTA
                secondaryButton
                howItWorksCard
                trustFooter
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.bubble.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 24)
            Text("他のブロッカーで\n消えない広告を見つけた？")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("URL を送信するだけ。自動で検証して、ブロックリストへ追加します。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var primaryCTA: some View {
        Button(action: onReportTap) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("広告を報告する")
                    .font(.system(.title3, design: .rounded, weight: .bold))
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
        .padding(.horizontal, 20)
    }

    private var secondaryButton: some View {
        Button(action: onHistoryTap) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 16, weight: .semibold))
                Text("これまでの報告履歴")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .padding(.horizontal, 20)
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("送信後のながれ")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            stepRow(
                icon: "doc.text.fill",
                title: "1. 報告 (約 1 分)",
                subtitle: "URL を貼り付けて送信。メモは任意です。"
            )
            stepRow(
                icon: "checkmark.seal.fill",
                title: "2. 自動で検証",
                subtitle: "重複報告や大手サイトを除外し、安全性をチェック。"
            )
            stepRow(
                icon: "shield.lefthalf.filled",
                title: "3. ブロックに反映",
                subtitle: "通常 7〜14 日でブロックリストに追加。本体アプリの更新は不要。"
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var trustFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.secondary)
            Text("報告は完全匿名 · URL のみ送信")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    NavigationStack {
        ReportEntryView(onReportTap: {}, onHistoryTap: {})
            .navigationTitle("報告")
    }
}
