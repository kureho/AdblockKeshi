import Foundation

/// Fetches the CDN-hosted feature-flags JSON. Abstracted so tests can swap a
/// stub for the URLSession-backed implementation.
public protocol RemoteConfigFetching {
    func fetch(url: URL) async throws -> Data
}

public struct URLSessionRemoteConfigFetcher: RemoteConfigFetching {
    public init() {}
    public func fetch(url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}

/// Caches the v3 feature-flags JSON in UserDefaults.
/// Behaviour on network failure is fail-open (last successful cache wins);
/// the FeatureFlags facade applies fail-CLOSED on top of this when the
/// emergency kill switch flips.
public final class RemoteConfigStore {
    public static let cachedJSONUserDefaultsKey = "v3.remoteConfig.cachedJSON"
    public static let fetchedAtUserDefaultsKey = "v3.remoteConfig.fetchedAt"

    public static let defaultURL = URL(
        string: "https://kureho.github.io/AdblockKeshi/cdn/feature-flags.json"
    )!

    public static let shared = RemoteConfigStore(
        url: defaultURL,
        fetcher: URLSessionRemoteConfigFetcher(),
        defaults: .standard,
        now: { Date() }
    )

    private let url: URL
    private let fetcher: RemoteConfigFetching
    private let defaults: UserDefaults
    private let now: () -> Date

    public init(
        url: URL,
        fetcher: RemoteConfigFetching,
        defaults: UserDefaults,
        now: @escaping () -> Date
    ) {
        self.url = url
        self.fetcher = fetcher
        self.defaults = defaults
        self.now = now
    }

    @discardableResult
    public func fetchAndUpdate() async -> Bool {
        do {
            let data = try await fetcher.fetch(url: url)
            guard
                let _ = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return false
            }
            defaults.set(data, forKey: Self.cachedJSONUserDefaultsKey)
            defaults.set(now().timeIntervalSince1970, forKey: Self.fetchedAtUserDefaultsKey)
            return true
        } catch {
            return false
        }
    }

    public func boolValue(forKey key: String, default defaultValue: Bool) -> Bool {
        guard
            let data = defaults.data(forKey: Self.cachedJSONUserDefaultsKey),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = dict[key] as? Bool
        else {
            return defaultValue
        }
        return value
    }
}
