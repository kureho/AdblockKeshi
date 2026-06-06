import Foundation

final class ReportHistoryCache {
    static let cacheKey = "v3.report.history.cache.v1"

    private let defaults: UserDefaults
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func load() -> ReportHistoryResponse? {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return nil }
        return try? decoder.decode(ReportHistoryResponse.self, from: data)
    }

    func save(_ response: ReportHistoryResponse) {
        guard let data = try? encoder.encode(response) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.cacheKey)
    }
}
