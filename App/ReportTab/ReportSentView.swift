import SwiftUI

struct ReportSentView: View {
    /// 直前の報告で選ばれた「どこで見たか」。文言の出し分けに使う。
    let seenIn: SeenIn
    let onAgainTap: () -> Void
    let onCloseTap: () -> Void

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

                Text(ReportSentMessage.body(for: seenIn))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
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
}

#Preview("Safari") {
    NavigationStack {
        ReportSentView(seenIn: .safari, onAgainTap: {}, onCloseTap: {})
    }
}

#Preview("Safari 以外のアプリ") {
    NavigationStack {
        ReportSentView(seenIn: .otherApp, onAgainTap: {}, onCloseTap: {})
    }
}
