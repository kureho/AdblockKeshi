import Foundation

/// Real API client using URLSession + Workers endpoints. Token caching via HMACTokenStore.
///
/// Phase 2 limitation: Turnstile WebView integration is deferred to Phase 5.
/// `requestToken` requires the caller to provide a turnstile_response; the report
/// form currently does NOT do this (it would call requestToken implicitly).
/// For Phase 2 dev, baseURL points to localhost wrangler dev or staging Workers.
final class ReportAPIClient: ReportAPIClientProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let uuidStore: DeviceUUIDStore
    private let tokenStore: HMACTokenStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL,
         session: URLSession = .shared,
         uuidStore: DeviceUUIDStore,
         tokenStore: HMACTokenStore = HMACTokenStore()) {
        self.baseURL = baseURL
        self.session = session
        self.uuidStore = uuidStore
        self.tokenStore = tokenStore
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func submitReport(url: URL, memo: String?) async throws {
        let token = try await acquireToken(scope: .submit)
        let uuidHash = try uuidStore.getUUIDHash()
        let endpoint = baseURL.appendingPathComponent("/v1/reports/submit")
        var request = makeBaseRequest(url: endpoint)
        let body = SubmitRequestDTO(token: token.value, uuidHash: uuidHash, url: url.absoluteString, memo: memo)
        request.httpBody = try encoder.encode(body)
        let _: SubmitResponseDTO = try await send(request)
    }

    // MARK: - private

    private func acquireToken(scope: TokenScope) async throws -> HMACToken {
        if let cached = await tokenStore.get(scope: scope) { return cached }
        // Phase 2 では Turnstile WebView 未統合のため、新規 token 取得には
        // requestToken を別途呼ぶ必要がある。Phase 5 で onboarding に統合。
        throw APIError.unauthorized
    }

    private func makeBaseRequest(url: URL) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("AdblockKeshi/3.0 (iOS)", forHTTPHeaderField: "User-Agent")
        return r
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.networkUnavailable
            }
            switch http.statusCode {
            case 200..<300:
                do { return try decoder.decode(T.self, from: data) }
                catch { throw APIError.decodingFailed }
            case 401, 403:
                throw APIError.unauthorized
            case 429:
                throw try APIError.fromBody(data: data, statusCode: 429)
            case 400:
                throw try APIError.fromBody(data: data, statusCode: 400)
            case 500..<600:
                throw APIError.serverError(statusCode: http.statusCode)
            default:
                throw APIError.serverError(statusCode: http.statusCode)
            }
        } catch let urlError as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(urlError.code) {
            throw APIError.networkUnavailable
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.decodingFailed
        }
    }
}

extension APIError {
    static func fromBody(data: Data, statusCode: Int) throws -> APIError {
        let dto = (try? JSONDecoder().decode(APIErrorResponseDTO.self, from: data))
        switch dto?.error {
        case "turnstile_failed": return .turnstileVerificationFailed
        case "rate_limit_exceeded": return .rateLimitExceeded(retryAfter: dto?.retryAfter ?? 3600)
        case "validation_failed":
            return .validationFailed(field: "url", reason: dto?.message ?? "validation_failed")
        case "banned":
            return .banned(level: 1, expiresAt: Date(timeIntervalSinceNow: dto?.retryAfter ?? 86400))
        case "unauthorized": return .unauthorized
        default: return .serverError(statusCode: statusCode)
        }
    }
}
