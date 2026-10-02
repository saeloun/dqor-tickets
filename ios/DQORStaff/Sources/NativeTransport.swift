import Foundation

struct NativeHTTPResponse: Sendable {
    let status: Int
    let url: URL
    let data: Data
}
protocol NativeHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> NativeHTTPResponse
}

/// No cookies, credential fallback, caching, custom trust bypass, or redirect following.
final class EphemeralNativeTransport: NativeHTTPTransport, @unchecked Sendable {
    private let session: URLSession
    private let delegate = RejectNativeRedirects()
    init() {
        session = URLSession(configuration: Self.secureConfiguration(), delegate: delegate, delegateQueue: nil)
    }
    static func secureConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return configuration
    }
    func send(_ request: URLRequest) async throws -> NativeHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, let url = response.url else { throw NativeAPIError.invalidResponse }
        return NativeHTTPResponse(status: response.statusCode, url: url, data: data)
    }
    func close() { session.invalidateAndCancel() }
    deinit { session.invalidateAndCancel() }
}
private final class RejectNativeRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct NativeConfiguration: Sendable {
    let origin: URL?
    let enabled: Bool
    let eventID: String
    let eventName: String
    let theme: EventTheme
    static let disabled = NativeConfiguration(origin: nil, enabled: false)
    init(origin: URL?, enabled: Bool = false, eventID: String = "dqor-2026", eventName: String = "DQOR 2026", theme: EventTheme = .indigo) {
        self.origin = origin; self.enabled = enabled; self.eventID = eventID; self.eventName = eventName; self.theme = theme
    }
    func validatedOrigin() throws -> URL {
        guard enabled else { throw NativeAPIError.disabled }
        guard let origin, let parts = URLComponents(url: origin, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw NativeAPIError.invalidConfiguration }
        return origin
    }
}

enum NativeAPIError: Error, LocalizedError, Equatable {
    case disabled, invalidConfiguration, invalidResponse, secureStorage, sessionChanged, sessionAlreadyActive, requestInProgress, rejected, rateLimited, unavailable, revocationUnconfirmed, moreResults
    var errorDescription: String? {
        switch self {
        case .disabled: "Live staff access is disabled. Use the demo until staging integration is approved."
        case .invalidConfiguration: "The staff server configuration is not valid."
        case .invalidResponse: "The server response could not be verified. Check-in is not confirmed. Ask an event administrator to verify attendance before retrying."
        case .secureStorage: "Secure session storage is unavailable. Sign-in or local session removal could not be completed."
        case .sessionChanged: "The session changed while the request was running. Sign in again."
        case .sessionAlreadyActive: "Sign out of the current staff session before signing in again."
        case .requestInProgress: "Another staff request is still running."
        case .rejected: "The server rejected this request. Check the selected event day and attendees."
        case .rateLimited: "Too many requests. Wait before trying again."
        case .unavailable: "The staff service is unavailable. Check-in is not confirmed."
        case .revocationUnconfirmed: "Signed out on this device. Server revocation was not confirmed; contact an administrator if needed."
        case .moreResults: "More attendees match. Refine the search; only the displayed attendees can be selected."
        }
    }
}
