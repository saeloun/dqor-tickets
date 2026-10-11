import Foundation

struct OwnedEvent: Decodable, Equatable, Identifiable, Sendable {
    struct Organizer: Decodable, Equatable, Sendable { let name, slug: String }
    let id, ownership, title, startsAt, endsAt, startDate, endDate, timezone, detailsPath: String
    let organizer: Organizer
    var website: URL { URL(string: OwnedEventsHTTPTransport.origin + detailsPath)! }
    static func validID(_ value: String) -> Bool {
        value.range(of: "^hosted-event-[1-9][0-9]{0,18}$", options: .regularExpression) != nil && Int64(value.dropFirst(13)) != nil
    }
    func validate() throws {
        guard Self.validID(id), ownership == "hosted_event", title.unicodeScalars.contains(where: { !$0.properties.isWhitespace }),
              title.unicodeScalars.count <= 255, organizer.name.unicodeScalars.contains(where: { !$0.properties.isWhitespace }), organizer.name.unicodeScalars.count <= 255,
              organizer.slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil,
              detailsPath.range(of: "^/events/" + organizer.slug + "/[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil,
              let namedZone = NSTimeZone(name: timezone), namedZone.data.starts(with: [0x54, 0x5a, 0x69, 0x66]),
              let zone = TimeZone(identifier: timezone), let start = Self.instant(startsAt), let end = Self.instant(endsAt), end > start else { throw OwnedEventsError.invalidResponse }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.string(from: start) == startDate, formatter.string(from: end) == endDate else { throw OwnedEventsError.invalidResponse }
    }
    static func instant(_ text: String) -> Date? {
        guard text.range(of: "(?:Z|[+-][0-9]{2}:[0-9]{2})$", options: .regularExpression) != nil else { return nil }
        let parser = ISO8601DateFormatter()
        if let value = parser.date(from: text) { return value }
        parser.formatOptions.insert(.withFractionalSeconds)
        return parser.date(from: text)
    }
}

struct OwnedEventsCatalog: Decodable, Equatable, Sendable {
    struct Pagination: Decodable, Equatable, Sendable { let page, perPage, total: Int }
    let schemaVersion: Int
    let contentVersion: String
    let events: [OwnedEvent]
    let pagination: Pagination
}

struct OwnedEventDetail: Decodable, Sendable {
    let schemaVersion: Int
    let contentVersion: String
    let event: OwnedEvent
}

enum OwnedEventsResource: Hashable, Sendable {
    case catalog(Int), detail(String)
    var url: URL? {
        switch self {
        case .catalog(let page):
            guard (1...1000).contains(page) else { return nil }
            return URL(string: OwnedEventsHTTPTransport.origin + "/api/public/v1/events?page=\(page)")
        case .detail(let id):
            guard OwnedEvent.validID(id) else { return nil }
            return URL(string: OwnedEventsHTTPTransport.origin + "/api/public/v1/events/" + id)
        }
    }
}

struct OwnedEventsResponse: Sendable { let status: Int; let etag: String?; let data: Data }
protocol OwnedEventsTransport: Sendable {
    func fetch(_ resource: OwnedEventsResource, ifNoneMatch: String?) async throws -> OwnedEventsResponse
}
enum OwnedEventsError: Error, Equatable { case invalidResponse, unsupportedSchema, unavailable, refreshInProgress }

actor OwnedEventsClient {
    struct State: Equatable, Sendable {
        var catalog: OwnedEventsCatalog?
        var event: OwnedEvent?
        var stale = true
        var unavailable = false
    }
    private let transport: any OwnedEventsTransport
    private var cache: [OwnedEventsResource: State] = [:]
    private var validators: [OwnedEventsResource: String] = [:]
    private var refreshing = Set<OwnedEventsResource>()
    private var generation = 0
    private var order: [OwnedEventsResource] = []
    init(transport: any OwnedEventsTransport) { self.transport = transport }
    func state(_ resource: OwnedEventsResource) -> State { cache[resource] ?? State() }
    func cancelPending() { generation += 1; refreshing.removeAll() }
    func clear() { cancelPending(); cache.removeAll(); validators.removeAll(); order.removeAll() }
    func markStale() {
        cancelPending()
        for key in cache.keys { cache[key]?.stale = true }
    }
    func refresh(_ resource: OwnedEventsResource) async throws -> State {
        guard resource.url != nil else { throw OwnedEventsError.invalidResponse }
        guard !refreshing.contains(resource) else { throw OwnedEventsError.refreshInProgress }
        refreshing.insert(resource)
        let requestGeneration = generation
        defer { if generation == requestGeneration { refreshing.remove(resource) } }
        do {
            let prior = state(resource)
            let hasSnapshot = prior.catalog != nil || prior.event != nil
            let validator = hasSnapshot ? validators[resource] : nil
            var response = try await transport.fetch(resource, ifNoneMatch: validator)
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw CancellationError() }
            if response.status == 304 {
                if let validator, hasSnapshot {
                    guard response.etag == nil || response.etag == validator else { throw OwnedEventsError.invalidResponse }
                    cache[resource]?.stale = false
                    return state(resource)
                }
                response = try await transport.fetch(resource, ifNoneMatch: nil)
                try Task.checkCancellation()
                guard generation == requestGeneration else { throw CancellationError() }
            }
            if response.status == 404 {
                cancelPending()
                switch resource {
                case .catalog: cache.removeAll(); validators.removeAll(); order.removeAll()
                case .detail:
                    for key in Array(cache.keys) { if case .catalog = key { cache.removeValue(forKey: key); validators.removeValue(forKey: key) } }
                }
                remember(State(stale: false, unavailable: true), for: resource)
                validators.removeValue(forKey: resource)
                return state(resource)
            }
            guard response.status == 200 else { throw response.status == 503 ? OwnedEventsError.unavailable : OwnedEventsError.invalidResponse }
            guard response.data.count <= OwnedEventsHTTPTransport.maximumBodyBytes else { throw OwnedEventsError.invalidResponse }
            try validateShape(response.data, resource: resource)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            struct Version: Decodable { let schemaVersion: Int; let contentVersion: String }
            guard let version = try? decoder.decode(Version.self, from: response.data) else { throw OwnedEventsError.invalidResponse }
            guard version.schemaVersion == 1 else { throw OwnedEventsError.unsupportedSchema }
            guard version.contentVersion.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw OwnedEventsError.invalidResponse }
            let next: State
            switch resource {
            case .catalog(let page):
                let catalog = try decoder.decode(OwnedEventsCatalog.self, from: response.data)
                guard catalog.pagination.page == page, catalog.pagination.perPage == 24, catalog.pagination.total >= 0,
                      catalog.events.count <= 24, catalog.events.count <= catalog.pagination.total, Set(catalog.events.map(\.id)).count == catalog.events.count else { throw OwnedEventsError.invalidResponse }
                try catalog.events.forEach { try $0.validate() }
                next = State(catalog: catalog, stale: false)
            case .detail(let id):
                let detail = try decoder.decode(OwnedEventDetail.self, from: response.data)
                try detail.event.validate()
                guard detail.event.id == id else { throw OwnedEventsError.invalidResponse }
                next = State(event: detail.event, stale: false)
            }
            remember(next, for: resource)
            validators[resource] = response.etag.flatMap { Self.validETag($0) ? $0 : nil }
            return next
        } catch {
            if generation == requestGeneration { cache[resource]?.stale = true }
            throw error
        }
    }
    private func remember(_ state: State, for resource: OwnedEventsResource) {
        cache[resource] = state
        order.removeAll { $0 == resource }
        order.append(resource)
        while order.count > 8 {
            let old = order.removeFirst()
            cache.removeValue(forKey: old)
            validators.removeValue(forKey: old)
        }
    }
    private func validateShape(_ data: Data, resource: OwnedEventsResource) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OwnedEventsError.invalidResponse }
        let events: [[String: Any]]
        switch resource {
        case .catalog:
            guard Set(root.keys) == ["schema_version", "content_version", "events", "pagination"],
                  let rows = root["events"] as? [[String: Any]], let pagination = root["pagination"] as? [String: Any],
                  Set(pagination.keys) == ["page", "per_page", "total"] else { throw OwnedEventsError.invalidResponse }
            events = rows
        case .detail:
            guard Set(root.keys) == ["schema_version", "content_version", "event"], let event = root["event"] as? [String: Any] else { throw OwnedEventsError.invalidResponse }
            events = [event]
        }
        for event in events {
            guard Set(event.keys) == ["id", "ownership", "title", "timezone", "starts_at", "ends_at", "start_date", "end_date", "organizer", "details_path"],
                  let organizer = event["organizer"] as? [String: Any], Set(organizer.keys) == ["name", "slug"] else { throw OwnedEventsError.invalidResponse }
        }
    }
    static func validETag(_ value: String) -> Bool {
        let prefix = value.hasPrefix("W/\"") ? 3 : value.hasPrefix("\"") ? 1 : 0
        guard prefix > 0, value.utf8.count <= 256, value.count > prefix + 1, value.hasSuffix("\"") else { return false }
        return !value.dropFirst(prefix).dropLast().unicodeScalars.contains { $0.value < 0x21 || $0.value > 0x7e || $0.value == 34 || $0.value == 92 }
    }
}

final class OwnedEventsHTTPTransport: OwnedEventsTransport, @unchecked Sendable {
    static let origin = "https://deccanqueenonrails.com"
    static let maximumBodyBytes = 1_048_576
    private let session: URLSession
    private let delegate = RejectOwnedEventsRedirects()
    init(configuration: URLSessionConfiguration = .ephemeral) {
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
    func fetch(_ resource: OwnedEventsResource, ifNoneMatch: String?) async throws -> OwnedEventsResponse {
        guard let url = resource.url else { throw OwnedEventsError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ifNoneMatch {
            guard OwnedEventsClient.validETag(ifNoneMatch) else { throw OwnedEventsError.invalidResponse }
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.url == url,
              response.expectedContentLength <= Self.maximumBodyBytes else { throw OwnedEventsError.invalidResponse }
        guard response.statusCode == 200 else { return OwnedEventsResponse(status: response.statusCode, etag: response.value(forHTTPHeaderField: "ETag"), data: Data()) }
        guard response.mimeType?.lowercased() == "application/json" else { throw OwnedEventsError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumBodyBytes else { throw OwnedEventsError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        return OwnedEventsResponse(status: 200, etag: response.value(forHTTPHeaderField: "ETag"), data: data)
    }
    deinit { session.invalidateAndCancel() }
}

private final class RejectOwnedEventsRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum OwnedEventsIntegration {
    static let productionEnabled = false
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--owned-events-fixture")
        #else
        productionEnabled
        #endif
    }
}
