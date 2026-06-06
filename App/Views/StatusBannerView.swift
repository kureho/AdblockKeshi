import SwiftUI

struct StatusBannerView: View {
    let banner: BannerType
    let onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.body.bold())
                    .foregroundStyle(.white)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(12)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch banner {
        case .yellow: return "exclamationmark.triangle.fill"
        case .red: return "xmark.octagon.fill"
        }
    }

    private var message: String {
        switch banner {
        case .yellow(let m), .red(let m): return m
        }
    }

    private var backgroundColor: Color {
        switch banner {
        case .yellow: return Color.orange
        case .red: return Color.red
        }
    }
}
