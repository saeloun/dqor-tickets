import XCTest
@testable import DQORStaff

private final class OwnedProtocolState: @unchecked Sendable {
    let lock = NSLock()
    var requests: [URLRequest] = []
    var status = 200
    var headers = ["Content-Type": "application/json", "ETag": "W/\"synthetic\""]
    var data = Data("{}".utf8)
    func update(status: Int? = nil, headers: [String: String]? = nil, data: Data? = nil, reset: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        if reset { requests = [] }
        if let status { self.status = status }
        if let headers { self.headers = headers }
        if let data { self.data = data }
    }
    func firstRequest() -> URLRequest? { lock.lock(); defer { lock.unlock() }; return requests.first }
}
private final class OwnedProtocolStub: URLProtocol {
    static let state = OwnedProtocolState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.lock.lock()
        Self.state.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.state.status, httpVersion: "HTTP/1.1", headerFields: Self.state.headers)!
        let data = Self.state.data
        Self.state.lock.unlock()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class OwnedEventsTransportTests: XCTestCase {
    override func setUp() {
        OwnedProtocolStub.state.update(status: 200, headers: ["Content-Type": "application/json", "ETag": "W/\"synthetic\""], data: Data("{}".utf8), reset: true)
    }
    private func transport() -> OwnedEventsHTTPTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OwnedProtocolStub.self]
        config.httpAdditionalHeaders = ["Authorization": "synthetic-must-be-removed", "Cookie": "synthetic-must-be-removed"]
        return OwnedEventsHTTPTransport(configuration: config)
    }
    func testInvalidIDAndUnsafeValidatorNeverIssueRequests() async throws {
        for resource in [OwnedEventsResource.detail("external-101"), .catalog(0)] {
            do { _ = try await transport().fetch(resource, ifNoneMatch: nil); XCTFail("Invalid resource") } catch { XCTAssertEqual(error as? OwnedEventsError, .invalidResponse) }
        }
        do { _ = try await transport().fetch(.catalog(1), ifNoneMatch: "synthetic\r\nheader"); XCTFail("Invalid validator") } catch { XCTAssertEqual(error as? OwnedEventsError, .invalidResponse) }
        XCTAssertNil(OwnedProtocolStub.state.firstRequest())
    }
    func testDetailRequestUsesStableOwnedIDOnly() async throws {
        _ = try await transport().fetch(.detail("hosted-event-101"), ifNoneMatch: nil)
        XCTAssertEqual(OwnedProtocolStub.state.firstRequest()?.url?.absoluteString, "https://deccanqueenonrails.com/api/public/v1/events/hosted-event-101")
    }
    func testFixedAnonymousRequestPreservesExactWeakValidator() async throws {
        let result = try await transport().fetch(.catalog(1), ifNoneMatch: "W/\"synthetic\"")
        XCTAssertEqual(result.status, 200)
        XCTAssertEqual(result.etag, "W/\"synthetic\"")
        let request = OwnedProtocolStub.state.firstRequest()
        XCTAssertEqual(request?.url, OwnedEventsResource.catalog(1).url)
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "If-None-Match"), "W/\"synthetic\"")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request?.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request?.httpBody)
        XCTAssertEqual(request?.httpShouldHandleCookies, false)
    }
    func testOversizedAdvertisedBodyAndNonJSONCannotBeAccepted() async throws {
        for headers in [["Content-Type": "application/json", "Content-Length": "\(OwnedEventsHTTPTransport.maximumBodyBytes + 1)"], ["Content-Type": "text/html"]] {
            OwnedProtocolStub.state.update(headers: headers)
            do { _ = try await transport().fetch(.catalog(1), ifNoneMatch: nil); XCTFail("Expected response rejection") }
            catch { XCTAssertEqual(error as? OwnedEventsError, .invalidResponse) }
        }
    }
    func testUnknownLengthStreamStopsAtBodyLimit() async throws {
        OwnedProtocolStub.state.update(data: Data(repeating: 32, count: OwnedEventsHTTPTransport.maximumBodyBytes + 1))
        do { _ = try await transport().fetch(.catalog(1), ifNoneMatch: nil); XCTFail("Expected streaming limit rejection") }
        catch { XCTAssertEqual(error as? OwnedEventsError, .invalidResponse) }
    }
    func testBodyless304IsReturnedWithoutInventingContent() async throws {
        OwnedProtocolStub.state.update(status: 304, data: Data())
        let result = try await transport().fetch(.catalog(1), ifNoneMatch: "W/\"synthetic\"")
        XCTAssertEqual(result.status, 304)
        XCTAssertTrue(result.data.isEmpty)
    }
}
