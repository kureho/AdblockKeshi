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
                Text("送信しました")
                    .font(.title2.bold())

                Text("通常 7-14 日以内、最悪 30 日以内に\n広告ブロックリストへ反映を検討します。\n結果はアプリ内通知でお知らせします。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: onAgainTap) {
                    Label("もう一度報告する", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onCloseTap) {
                    Text("ブロッカー タブに戻る")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
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
