import SwiftUI

struct ReportHistoryItemView: View {
    let item: ReportHistoryItem

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    var shouldShowRedactBadge: Bool { item.memoRedacted }

    var displayURL: String {
        let maxLen = 60
        if item.url.count <= maxLen { return item.url }
        let prefix = item.url.prefix(maxLen - 3)
        return prefix + "..."
    }

    var displayDate: String {
        Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(displayURL)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Spacer()
                statusBadge
            }

            HStack(spacing: 8) {
                Text(displayDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if shouldShowRedactBadge {
                    redactBadge
                }
            }

            if let memo = item.memo, !memo.isEmpty {
                Text(memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Text(item.status.detailDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(item.status.displayLabel)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(item.status.badgeRole.color.opacity(0.15))
            .foregroundStyle(item.status.badgeRole.color)
            .clipShape(Capsule())
    }

    private var redactBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "eye.slash.fill").font(.caption2)
            Text("一部伏字").font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .foregroundStyle(Color.orange)
        .clipShape(Capsule())
    }
}
