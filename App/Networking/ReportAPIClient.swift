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

    func submitReport(url: URL, memo: String?, adType: AdType?,
                      seenIn: SeenIn, diagnostics: ReportDiagnostics) async throws {
        let token = try await acquireToken(scope: .submit)
        let uuidHash = try uuidStore.getUUIDHash()
        let endpoint = baseURL.appendingPathComponent("/v1/reports/submit")
        var request = makeBaseRequest(url: endpoint)
        let body = SubmitRequestDTO(
            token: token.value,
            uuidHash: uuidHash,
            url: url.absoluteString,
            memo: memo,
            adType: adType?.rawValue,
            seenIn: seenIn.rawValue,
            blockerEnabled: diagnostics.blockerEnabled,
            dnsEnabled: diagnostics.dnsEnabled,
            appVersion: diagnostics.appVersion,
            appBuild: diagnostics.appBuild,
            filterVersion: diagnostics.filterVersion
        )
        request.httpBody = try encoder.encode(body)
        let _: SubmitResponseDTO = try await send(request)
    }

    func requestToken(turnstileResponse: String, scope: TokenScope) async throws {
        let uuidHash = try uuidStore.getUUIDHash()
        let endpoint = baseURL.appendingPathComponent("/v1/reports/token")
        var request = makeBaseRequest(url: endpoint)
        let body = TokenRequestDTO(
            turnstileResponse: turnstileResponse,
            scope: scope.rawValue,
            uuidHash: uuidHash
        )
        request.httpBody = try encoder.encode(body)
        let dto: TokenResponseDTO = try await send(request)
        let token = HMACToken(value: dto.token, scope: scope, expiresAt: dto.expiresAt)
        await tokenStore.set(token)
    }

    // MARK: - private

    private func acquireToken(scope: TokenScope) async throws -> HMACToken {
        if let cached = await tokenStore.get(scope: scope) { return cached }
        // No cached token. Caller must `requestToken(turnstileResponse:)` first.
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
            // D-lite: 保護ドメインの拒否は廃止した（報告は「広告が消えなかったページ」の
            // 改善用データなので yahoo.co.jp 等を送るのは正常な操作）。
            // ここへ来るのは URL 形式・memo 長など、入力を直せば通るものだけ。
            return .validationFailed(field: "url", reason: dto?.message ?? "validation_failed")
        case "banned":
            return .banned(level: 1, expiresAt: Date(timeIntervalSinceNow: dto?.retryAfter ?? 86400))
        case "unauthorized": return .unauthorized
        default: return .serverError(statusCode: statusCode)
        }
    }
}
