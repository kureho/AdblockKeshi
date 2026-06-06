import Foundation

enum TokenScope: String, Codable, CaseIterable, Sendable {
    case submit
    case history
    case delete
}

struct HMACToken: Equatable, Codable, Sendable {
    let value: String
    let scope: TokenScope
    let expiresAt: Date

    func isValid(now: Date = Date(), skew: TimeInterval = 30) -> Bool {
        return expiresAt > now.addingTimeInterval(skew)
    }
}

/// Thread-safe in-memory token cache. Tokens cleared between app launches.
actor HMACTokenStore {
    private var tokens: [TokenScope: HMACToken] = [:]

    func get(scope: TokenScope) -> HMACToken? {
        guard let token = tokens[scope], token.isValid() else {
            tokens.removeValue(forKey: scope)
            return nil
        }
        return token
    }

    func set(_ token: HMACToken) {
        tokens[token.scope] = token
    }

    func invalidate(scope: TokenScope) {
        tokens.removeValue(forKey: scope)
    }

    func invalidateAll() {
        tokens.removeAll()
    }
}
