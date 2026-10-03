import Foundation

/// Public programme v1 DTOs. Text is plain display text; optional times stay unscheduled.
struct PublicProgramme: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let contentVersion: String
    let event: Event
    let sessions: [Session]
    let speakers: [Speaker]
    struct Event: Decodable, Equatable, Sendable {
        let id, title, startDate, endDate, timezone, venue, publicUrl: String
    }
    struct Session: Decodable, Equatable, Sendable {
        let id, title: String
        let abstract, startsAt, endsAt, localDate, speakerId, speakerName, room: String?
    }
    struct Speaker: Decodable, Equatable, Sendable {
        let id, name, profileUrl: String
        let title, bio: String?
    }
}

struct ProgrammeResponse: Sendable {
    let status: Int
    let etag: String?
    let data: Data
}

protocol ProgrammeTransport: Sendable {
    func fetch(ifNoneMatch: String?) async throws -> ProgrammeResponse
}

enum ProgrammeError: Error, Equatable {
    case unsupportedSchema, invalidResponse, unavailable, refreshInProgress
}

actor PublicProgrammeClient {
    struct State: Equatable, Sendable {
        var snapshot: PublicProgramme?
        var isStale = true
    }
    private let transport: any ProgrammeTransport
    private var cached = State()
    private var etag: String?
    private var refreshingGeneration: Int?
    private var generation = 0
    init(transport: any ProgrammeTransport) { self.transport = transport }
    func state() -> State { cached }
    func clear() {
        generation += 1
        cached = State()
        etag = nil
        refreshingGeneration = nil
    }

    @discardableResult
    func refresh() async throws -> State {
        guard refreshingGeneration == nil else { throw ProgrammeError.refreshInProgress }
        let requestGeneration = generation
        refreshingGeneration = requestGeneration
        defer { if refreshingGeneration == requestGeneration { refreshingGeneration = nil } }
        do {
            let validator = cached.snapshot == nil ? nil : etag
            var response = try await transport.fetch(ifNoneMatch: validator)
            try Task.checkCancellation()
            guard requestGeneration == generation else { throw CancellationError() }
            if response.status == 304 {
                if let validator, cached.snapshot != nil {
                    guard response.etag == nil || response.etag == validator else { throw ProgrammeError.invalidResponse }
                    cached.isStale = false
                    return cached
                }
                // A bodyless 304 cannot establish a snapshot. Retry unconditionally once.
                response = try await transport.fetch(ifNoneMatch: nil)
                try Task.checkCancellation()
                guard requestGeneration == generation else { throw CancellationError() }
            }
            guard response.status == 200 else {
                throw response.status == 503 ? ProgrammeError.unavailable : ProgrammeError.invalidResponse
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            struct Version: Decodable { let schemaVersion: Int }
            guard let version = try? decoder.decode(Version.self, from: response.data) else {
                throw ProgrammeError.invalidResponse
            }
            guard version.schemaVersion == 1 else { throw ProgrammeError.unsupportedSchema }
            guard let snapshot = try? decoder.decode(PublicProgramme.self, from: response.data),
                  Set(snapshot.sessions.map(\.id)).count == snapshot.sessions.count,
                  Set(snapshot.speakers.map(\.id)).count == snapshot.speakers.count else {
                throw ProgrammeError.invalidResponse
            }
            // Atomic authoritative replacement also removes withdrawn sessions/speakers.
            cached = State(snapshot: snapshot, isStale: false)
            etag = response.etag
            return cached
        } catch {
            if requestGeneration == generation { cached.isStale = true }
            throw error
        }
    }
}
