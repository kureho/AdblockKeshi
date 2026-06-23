import SwiftUI

struct ReportSentView: View {
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
                Text("報告を受け付けました")
                    .font(.title2.bold())

                Text("安全に反映できる広告は、この端末の保護へ追加されます。\n複数の利用者から届いた報告は、確認後に全体の保護へ反映されることがあります。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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

#Preview {
    NavigationStack {
        ReportSentView(onAgainTap: {}, onCloseTap: {})
    }
}
