import Foundation

final class PublicProgrammeHTTPTransport: ProgrammeTransport, @unchecked Sendable {
    static let endpoint = URL(string: "https://deccanqueenonrails.com/api/public/v1/dqor/programme")!
    static let maximumBodyBytes = 2 * 1024 * 1024
    private let session: URLSession
    private let delegate = RejectPublicProgrammeRedirects()
    init(configuration: URLSessionConfiguration = EphemeralNativeTransport.secureConfiguration()) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
    func fetch(ifNoneMatch: String?) async throws -> ProgrammeResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ifNoneMatch { request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.url == Self.endpoint,
              response.expectedContentLength <= Self.maximumBodyBytes else { throw ProgrammeError.invalidResponse }
        if response.statusCode == 304 { return ProgrammeResponse(status: 304, etag: response.value(forHTTPHeaderField: "ETag"), data: Data()) }
        guard response.statusCode == 200 else {
            return ProgrammeResponse(status: response.statusCode, etag: nil, data: Data())
        }
        guard response.mimeType?.lowercased() == "application/json" else { throw ProgrammeError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumBodyBytes else { throw ProgrammeError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        return ProgrammeResponse(status: response.statusCode, etag: response.value(forHTTPHeaderField: "ETag"), data: data)
    }
    deinit { session.invalidateAndCancel() }
}

private final class RejectPublicProgrammeRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
