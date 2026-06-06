import SwiftUI

struct ReportEntryView: View {
    let onReportTap: () -> Void
    let onHistoryTap: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 32)
                    Text("他のブロッカーで\n消えない広告を見つけた？")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("このアプリに教えると、自動で対応します。\n通常 7-14 日以内、最悪 30 日以内にブロックリストへ反映します。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 8)

                // Primary CTA
                Button(action: onReportTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("報告する")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)

                // Secondary
                Button(action: onHistoryTap) {
                    Label("これまでの報告履歴", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    NavigationStack {
        ReportEntryView(onReportTap: {}, onHistoryTap: {})
    }
}
