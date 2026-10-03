import Foundation

struct AttendeeSessionPage: Codable, Sendable {
    let schemaVersion: Int
    let event: String
    let clientID: String
    let capabilities: [String]
    let expiresAt: String
    let checkedAt: String
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", event, clientID = "client_id", capabilities, expiresAt = "expires_at", checkedAt = "checked_at" }
}
struct AttendeeServiceFailure: Error, Equatable, Sendable {
    enum Code: String, Codable, Sendable {
        case invalidRequest = "invalid_request", invalidGrant = "invalid_grant", unauthenticated, httpsRequired = "https_required", invalidConsent = "invalid_consent", notFound = "not_found", invalidAttempt = "invalid_attempt", invalidCursor = "invalid_cursor", rateLimited = "rate_limited", configurationUnavailable = "configuration_unavailable", temporarilyUnavailable = "temporarily_unavailable"
    }
    let code: Code
    let retryAfter: Int?
    var reason: AttendeeAuthError {
        switch code {
        case .invalidGrant, .invalidAttempt: .invalidCallback
        case .unauthenticated: .revoked
        case .notFound, .configurationUnavailable, .httpsRequired: .unavailable
        case .rateLimited: .rateLimited
        case .temporarilyUnavailable: .serviceUnavailable
        case .invalidRequest, .invalidConsent, .invalidCursor: .invalidResponse
        }
    }
}
struct AttendeeHTTPResponse: Sendable {
    let status: Int
    let url: URL
    let headers: [String: String]
    let body: Data
}
protocol AttendeeHTTPTransport: Sendable {
    var synthetic: Bool { get }
    func send(_ request: URLRequest) async throws -> AttendeeHTTPResponse
}
final class AttendeeHTTPSessionTransport: AttendeeHTTPTransport, @unchecked Sendable {
    let synthetic: Bool
    private let session: URLSession
    private let delegate = AttendeeSessionDelegate()
    static let bodyLimit = 256 * 1024
    init() {
        synthetic = false
        session = URLSession(configuration: Self.configuration(), delegate: delegate, delegateQueue: nil)
    }
    #if DEBUG
    init(fixtureProtocol: URLProtocol.Type) {
        synthetic = true
        let configuration = Self.configuration(); configuration.protocolClasses = [fixtureProtocol]
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
    #endif
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil; configuration.httpAdditionalHeaders = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return configuration
    }
    func send(_ request: URLRequest) async throws -> AttendeeHTTPResponse {
        guard AttendeeActivation.liveEnabled || synthetic else { throw AttendeeAuthError.unavailable }
        guard Self.canonical(request) else { throw AttendeeAuthError.invalidResponse }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, let url = http.url, url == request.url,
              http.expectedContentLength <= Int64(Self.bodyLimit) else { throw AttendeeAuthError.invalidResponse }
        var body = Data()
        for try await byte in bytes {
            guard body.count < Self.bodyLimit else { throw AttendeeAuthError.invalidResponse }
            body.append(byte)
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { output, item in
            if let name = item.key as? String, let value = item.value as? String { output[name.lowercased()] = value }
        }
        return AttendeeHTTPResponse(status: http.statusCode, url: url, headers: headers, body: body)
    }
    static func canonical(_ request: URLRequest) -> Bool {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "deccanqueenonrails.com", parts.percentEncodedHost == "deccanqueenonrails.com", parts.port == nil,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              !request.httpShouldHandleCookies,
              Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }).isSubset(of: ["accept", "content-type", "authorization"]),
              request.value(forHTTPHeaderField: "Accept") == "application/json" else { return false }
        let base = "/api/native/attendee/v1/"
        guard parts.percentEncodedPath.hasPrefix(base) else { return false }
        let path = String(parts.percentEncodedPath.dropFirst(base.count))
        if path == "token" {
            guard request.httpMethod == "POST", parts.query == nil, request.value(forHTTPHeaderField: "Authorization") == nil,
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json", let body = request.httpBody, body.count <= 4096,
                  let payload = try? JSONSerialization.jsonObject(with: body) as? [String: String], Set(payload.keys) == Set(["code", "code_verifier", "client_id", "redirect_uri"]),
                  NativeAttendeeAPI.opaque(payload["code"] ?? "", prefix: "nac1_"), let verifier = payload["code_verifier"], (43...128).contains(verifier.utf8.count),
                  verifier.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45,46,95,126].contains($0) }),
                  payload["client_id"] == "dqor-ios", payload["redirect_uri"] == "https://deccanqueenonrails.com/native/attendee/ios/callback" else { return false }
            return true
        }
        guard ["account", "passes", "session"].contains(path), request.httpMethod == "GET" || (path == "session" && request.httpMethod == "DELETE"),
              request.httpBody == nil, request.httpBodyStream == nil,
              let header = request.value(forHTTPHeaderField: "Authorization"), header.hasPrefix("Bearer "), NativeAttendeeAPI.opaque(String(header.dropFirst(7)), prefix: "na1_") else { return false }
        if parts.query != nil {
            guard path == "passes", let query = parts.queryItems, query.count == 1, query[0].name == "cursor", let cursor = query[0].value, AttendeeSessionStore.validCursor(cursor), parts.percentEncodedQuery == "cursor=\(cursor)" else { return false }
        }
        return true
    }
    deinit { session.invalidateAndCancel() }
}
private final class AttendeeSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}
struct NativeAttendeeAPI: AttendeeBridgeAPI {
    private let transport: any AttendeeHTTPTransport
    init(transport: any AttendeeHTTPTransport = AttendeeHTTPSessionTransport()) { self.transport = transport }
    static let capabilities = ["account:read", "passes:read"]
    static func opaque(_ value: String, prefix: String) -> Bool {
        guard value.hasPrefix(prefix), value.utf8.count == prefix.utf8.count + 43 else { return false }
        return value.dropFirst(prefix.count).utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }
    static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: string)
    }
    private func request(_ path: String, method: String = "GET", lease: AttendeeLease? = nil, cursor: String? = nil, body: Data? = nil) throws -> URLRequest {
        var parts = URLComponents(string: "https://deccanqueenonrails.com/api/native/attendee/v1/\(path)")!
        if let cursor {
            guard path == "passes", AttendeeSessionStore.validCursor(cursor) else { throw AttendeeAuthError.invalidResponse }
            parts.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        }
        var request = URLRequest(url: parts.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let lease {
            guard Self.opaque(lease.token, prefix: "na1_") else { throw AttendeeAuthError.invalidResponse }
            request.setValue("Bearer \(lease.token)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    private func send(_ request: URLRequest, success: Int = 200) async throws -> AttendeeHTTPResponse {
        guard AttendeeActivation.liveEnabled || transport.synthetic else { throw AttendeeAuthError.unavailable }
        let result = try await transport.send(request)
        guard result.url == request.url, result.body.count <= AttendeeHTTPSessionTransport.bodyLimit else { throw AttendeeAuthError.invalidResponse }
        if result.status == 204 && success == 204 {
            guard result.body.isEmpty else { throw AttendeeAuthError.invalidResponse }
            return result
        }
        guard result.headers["content-type"]?.split(separator: ";").first?.lowercased() == "application/json" else { throw AttendeeAuthError.invalidResponse }
        if result.status != success {
            struct Failure: Decodable { struct Detail: Decodable { let code: AttendeeServiceFailure.Code }; let schema_version: Int; let error: Detail }
            guard let failure = try? JSONDecoder().decode(Failure.self, from: result.body), failure.schema_version == 1 else { throw AttendeeAuthError.invalidResponse }
            let allowed: [Int: Set<AttendeeServiceFailure.Code>] = [400: [.invalidRequest], 401: request.url?.path == "/api/native/attendee/v1/token" ? [.invalidGrant] : [.unauthenticated], 403: [.httpsRequired, .invalidConsent], 404: [.notFound], 409: [.invalidAttempt], 422: [.invalidCursor], 429: [.rateLimited], 503: [.configurationUnavailable, .temporarilyUnavailable]]
            guard allowed[result.status]?.contains(failure.error.code) == true else { throw AttendeeAuthError.invalidResponse }
            let retry = result.status == 429 ? Int(result.headers["retry-after"] ?? "") : nil
            guard result.status != 429 || retry == 180 else { throw AttendeeAuthError.invalidResponse }
            throw AttendeeServiceFailure(code: failure.error.code, retryAfter: retry)
        }
        return result
    }
    func exchange(_ exchange: AttendeeCodeExchange) async throws -> AttendeeLease {
        guard Self.opaque(exchange.code, prefix: "nac1_"), (43...128).contains(exchange.verifier.utf8.count), exchange.verifier.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45,46,95,126].contains($0) }) else { throw AttendeeAuthError.invalidCallback }
        let body = try JSONSerialization.data(withJSONObject: ["code": exchange.code, "code_verifier": exchange.verifier, "client_id": exchange.clientID, "redirect_uri": exchange.redirectURI])
        let response = try await send(request("token", method: "POST", body: body))
        struct Token: Decodable { let access_token: String; let token_type: String; let expires_at: String; let event: String; let capabilities: [String] }
        guard let keys = try JSONSerialization.jsonObject(with: response.body) as? [String: Any], Set(keys.keys) == Set(["access_token", "token_type", "expires_at", "event", "capabilities"]) else { throw AttendeeAuthError.invalidResponse }
        let token = try JSONDecoder().decode(Token.self, from: response.body)
        guard Self.opaque(token.access_token, prefix: "na1_"), token.token_type == "Bearer", token.event == "dqor-2026", token.capabilities.sorted() == Self.capabilities.sorted(), let expiry = Self.date(token.expires_at) else { throw AttendeeAuthError.invalidResponse }
        return AttendeeLease(token: token.access_token, expiresAt: expiry)
    }
    private func decode<T: Decodable>(_ type: T.Type, _ response: AttendeeHTTPResponse) throws -> T { do { return try JSONDecoder().decode(type, from: response.body) } catch { throw AttendeeAuthError.invalidResponse } }
    func account(_ lease: AttendeeLease) async throws -> AttendeeAccountPage { try decode(AttendeeAccountPage.self, await send(request("account", lease: lease))) }
    func passes(_ lease: AttendeeLease, cursor: String?) async throws -> AttendeePassPage { try decode(AttendeePassPage.self, await send(request("passes", lease: lease, cursor: cursor))) }
    func session(_ lease: AttendeeLease) async throws -> AttendeeSessionPage {
        let response = try await send(request("session", lease: lease))
        guard let payload = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any], Set(payload.keys) == Set(["schema_version", "event", "client_id", "capabilities", "expires_at", "checked_at"]) else { throw AttendeeAuthError.invalidResponse }
        return try decode(AttendeeSessionPage.self, response)
    }
    func revoke(_ lease: AttendeeLease) async throws { _ = try await send(request("session", method: "DELETE", lease: lease), success: 204) }
}
