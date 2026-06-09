import Foundation
import SwiftUI

/// 端末ローカルで報告履歴を保持する store。
///
/// 「URL のみ送信・完全匿名」の運用方針上、サーバー側に UUID 紐付きの履歴を
/// 保持できないため、送信成功時に端末側へ append する。`ReportHistoryItem` 単位で
/// id（UUID 文字列）を付け、swipe 削除はその id で remove する。
@MainActor
final class LocalReportHistoryStore: ObservableObject {
    static let storageKey = "v3.report.history.local.v1"

    @Published private(set) var items: [ReportHistoryItem] = []

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.items = loadFromDisk()
    }

    /// 報告送信成功時に呼ぶ。新しい行は先頭へ。
    func append(url: URL, memo: String?) {
        let item = ReportHistoryItem(
            id: UUID().uuidString,
            url: url.absoluteString,
            memo: memo,
            memoRedacted: false,
            status: .pending,
            createdAt: Date(),
            validatedAt: nil,
            appliedAt: nil
        )
        items.insert(item, at: 0)
        persist()
    }

    /// swipe 削除のための index 削除。
    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        persist()
    }

    /// id 指定削除（将来のため。テスト等で利用）。
    func delete(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    // MARK: - private

    private func persist() {
        if let data = try? encoder.encode(items) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func loadFromDisk() -> [ReportHistoryItem] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? decoder.decode([ReportHistoryItem].self, from: data)
        else { return [] }
        return decoded
    }
}
