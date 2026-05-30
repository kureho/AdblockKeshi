import SwiftUI

struct OnboardingView: View {
    let onReady: () -> Void

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
                    StepRow(
                        number: 3,
                        title: "「広告消し」を ON",
                        detail: "スイッチを1回だけONにします"
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
