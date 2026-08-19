import SwiftUI

struct ReportSentView: View {
    /// 直前の報告の結果（種別・どこで見たか・host）。文言と一時オフ提示の出し分けに使う。
    let success: ReportSuccess
    let onAgainTap: () -> Void
    let onCloseTap: () -> Void

    /// 「このサイトで一時オフ」を押したか（押したら確認表示に切り替える）。
    @State private var exceptionAdded = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.green)

            VStack(spacing: 12) {
                Text(ReportSentMessage.title)
                    .font(.title2.bold())

                Text(ReportSentMessage.body(for: success))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if success.offersSiteException {
                siteExceptionCard
                    .padding(.horizontal, 20)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: onAgainTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("もう一度報告する")
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

                Button(action: onCloseTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 18, weight: .semibold))
                        Text("ブロッカー タブに戻る")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(uiColor: .systemGray5))
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationBarBackButtonHidden(true)
    }

    /// v4.2.0: Safari の壊れ報告のみ。「このサイトで一時オフ」＝per-site 例外を今すぐ効かせる。
    private var siteExceptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if exceptionAdded {
                Label("\(success.host) ではブロックを停止しました", systemImage: "checkmark.circle")
                    .font(.footnote.weight(.semibold))
                Text("停止中のサイトは、ブロッカータブの「ブロック停止中のサイト」からいつでも戻せます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("このサイトの表示が直るまで、ブロックをオフにしておけます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    guard let store = SiteExceptionsStore.sharedAppGroup(),
                          (try? store.add(success.host)) != nil else { return }
                    CombinedRuleListCoordinator.scheduleRegenerate()
                    exceptionAdded = true
                } label: {
                    Label("このサイトでブロックを一時オフ", systemImage: "pause.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

#Preview("広告報告 (Safari)") {
    NavigationStack {
        ReportSentView(
            success: ReportSuccess(kind: .adNotBlocked, seenIn: .safari, host: "example.com"),
            onAgainTap: {}, onCloseTap: {})
    }
}

#Preview("壊れ報告 (Safari)") {
    NavigationStack {
        ReportSentView(
            success: ReportSuccess(kind: .siteBroken, seenIn: .safari, host: "news.example.com"),
            onAgainTap: {}, onCloseTap: {})
    }
}

#Preview("壊れ報告 (アプリ内)") {
    NavigationStack {
        ReportSentView(
            success: ReportSuccess(kind: .siteBroken, seenIn: .otherApp, host: "example.com"),
            onAgainTap: {}, onCloseTap: {})
    }
}
