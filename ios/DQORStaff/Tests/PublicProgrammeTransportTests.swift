import XCTest
@testable import DQORStaff

private final class PublicProtocolState: @unchecked Sendable {
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
private final class PublicProtocolStub: URLProtocol {
    static let state = PublicProtocolState()
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
final class PublicProgrammeTransportTests: XCTestCase {
    override func setUp() {
        PublicProtocolStub.state.update(status: 200, headers: ["Content-Type": "application/json", "ETag": "W/\"synthetic\""], data: Data("{}".utf8), reset: true)
    }
    private func transport() -> PublicProgrammeHTTPTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PublicProtocolStub.self]
        config.httpAdditionalHeaders = ["Authorization": "synthetic-must-be-removed", "Cookie": "synthetic-must-be-removed"]
        return PublicProgrammeHTTPTransport(configuration: config)
    }
    func testFixedAnonymousRequestPreservesExactWeakValidator() async throws {
        let result = try await transport().fetch(ifNoneMatch: "W/\"synthetic\"")
        XCTAssertEqual(result.status, 200)
        XCTAssertEqual(result.etag, "W/\"synthetic\"")
        let request = PublicProtocolStub.state.firstRequest()
        XCTAssertEqual(request?.url, PublicProgrammeHTTPTransport.endpoint)
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "If-None-Match"), "W/\"synthetic\"")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request?.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request?.httpBody)
        XCTAssertEqual(request?.httpShouldHandleCookies, false)
    }
    func testOversizedAdvertisedBodyAndNonJSONCannotBeAccepted() async throws {
        for headers in [["Content-Type": "application/json", "Content-Length": "\(PublicProgrammeHTTPTransport.maximumBodyBytes + 1)"], ["Content-Type": "text/html"]] {
            PublicProtocolStub.state.update(headers: headers)
            do { _ = try await transport().fetch(ifNoneMatch: nil); XCTFail("Expected response rejection") }
            catch { XCTAssertEqual(error as? ProgrammeError, .invalidResponse) }
        }
    }
    func testUnknownLengthStreamStopsAtBodyLimit() async throws {
        PublicProtocolStub.state.update(data: Data(repeating: 32, count: PublicProgrammeHTTPTransport.maximumBodyBytes + 1))
        do { _ = try await transport().fetch(ifNoneMatch: nil); XCTFail("Expected streaming limit rejection") }
        catch { XCTAssertEqual(error as? ProgrammeError, .invalidResponse) }
    }
    func testBodyless304IsReturnedWithoutInventingContent() async throws {
        PublicProtocolStub.state.update(status: 304, data: Data())
        let result = try await transport().fetch(ifNoneMatch: "W/\"synthetic\"")
        XCTAssertEqual(result.status, 304)
        XCTAssertTrue(result.data.isEmpty)
    }
}
