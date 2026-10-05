import SwiftUI
import CryptoKit
import Security

enum AttendeeAuthError: Error, Equatable {
    case unavailable, unsupportedPlatform, invalidCallback, expired, invalidResponse, revoked, offline, uncertainExchange, canceled, rateLimited, serviceUnavailable
    var message: String {
        switch self {
        case .unavailable: "Native account access is not available yet. Open your account on the official website."
        case .unsupportedPlatform: "Use your account on the official website. Native account features are unavailable on this iOS version."
        case .invalidCallback: "The sign-in return could not be verified. Start a new sign-in."
        case .expired: "Your private session has expired. Sign in again when native access is available."
        case .invalidResponse: "Private account data could not be verified. No ticket credential is available here."
        case .revoked: "Your private session is no longer valid. Sign in again."
        case .offline: "Connection unavailable. Private information has not been revalidated."
        case .uncertainExchange: "Sign-in could not be confirmed. Start a new sign-in; this return cannot be reused."
        case .canceled: "Sign-in canceled."
        case .rateLimited: "Too many requests. Wait three minutes before trying again."
        case .serviceUnavailable: "Private account access is temporarily unavailable. Try again later."
        }
    }
}
struct AttendeeLease: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let token: String
    let expiresAt: Date
    var description: String { "AttendeeLease(redacted)" }
    var debugDescription: String { description }
}
struct AttendeeAccount: Codable, Equatable, Sendable {
    let id: String
    let name: String?
    let email: String
}
struct AttendeeAccountPage: Codable, Sendable {
    let schemaVersion: Int
    let event: String
    let checkedAt: String
    let account: AttendeeAccount
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", event, checkedAt = "checked_at", account }
}
struct AttendeePass: Codable, Identifiable, Equatable, Sendable {
    struct PassType: Codable, Equatable, Sendable { let id: String; let name: String }
    struct Admission: Codable, Equatable, Sendable {
        let startsOn: String?
        let endsOn: String?
        enum CodingKeys: String, CodingKey { case startsOn = "starts_on", endsOn = "ends_on" }
    }
    struct Entry: Codable, Equatable, Sendable {
        let date: String
        let eligible: Bool
        let checkedInAt: String?
        enum CodingKeys: String, CodingKey { case date, eligible, checkedInAt = "checked_in_at" }
    }
    let id: String
    let type: PassType
    let status: String
    let admission: Admission
    let entry: [Entry]
}
struct AttendeePassPage: Codable, Sendable {
    let schemaVersion: Int
    let event: String
    let checkedAt: String
    let passes: [AttendeePass]
    let moreResults: Bool
    let nextCursor: String?
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", event, checkedAt = "checked_at", passes, moreResults = "more_results", nextCursor = "next_cursor"
    }
}
struct AttendeeCodeExchange: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let code: String
    let verifier: String
    let clientID = "dqor-ios"
    let redirectURI = "https://deccanqueenonrails.com/native/attendee/ios/callback"
    var description: String { "AttendeeCodeExchange(redacted)" }
    var debugDescription: String { description }
}
protocol AttendeeBridgeAPI: Sendable {
    func exchange(_ exchange: AttendeeCodeExchange) async throws -> AttendeeLease
    func account(_ lease: AttendeeLease) async throws -> AttendeeAccountPage
    func passes(_ lease: AttendeeLease, cursor: String?) async throws -> AttendeePassPage
    func session(_ lease: AttendeeLease) async throws -> AttendeeSessionPage
    func revoke(_ lease: AttendeeLease) async throws
}
@MainActor
protocol AttendeeBrowserAuthorizing: AnyObject {
    func authorize(_ url: URL) async throws -> URL
    func cancel()
    func receiveExternal(_ url: URL) -> Bool
}
enum AttendeePlatformPolicy {
    static var supportsHTTPSCallback: Bool {
        if #available(iOS 17.4, *) { return true }
        return false
    }
}
enum AttendeeActivation { static let liveEnabled = false }
enum AttendeeElapsedClock {
    private static let clock = ContinuousClock()
    private static let origin = clock.now
    static func now() -> TimeInterval {
        let elapsed = origin.duration(to: clock.now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
    }
}
struct AttendeeLoginTransaction: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let state: String
    let verifier: String
    let startedUptime: TimeInterval
    var description: String { "AttendeeLoginTransaction(redacted)" }
    var debugDescription: String { description }
    init(uptime: TimeInterval) throws {
        state = try Self.random(); verifier = try Self.random(); startedUptime = uptime
    }
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AttendeeAuthError.unavailable }
        return base64URL(Data(bytes))
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    var challenge: String { Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    var authorizeURL: URL {
        var parts = URLComponents(string: "https://deccanqueenonrails.com/account/native/authorize")!
        parts.queryItems = [URLQueryItem(name: "client_id", value: "dqor-ios"), URLQueryItem(name: "redirect_uri", value: "https://deccanqueenonrails.com/native/attendee/ios/callback"), URLQueryItem(name: "state", value: state), URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "S256")]
        return parts.url!
    }
    func exchange(callback: URL, uptime: TimeInterval) throws -> AttendeeCodeExchange {
        guard callback.absoluteString.utf8.count <= 4096, uptime >= startedUptime, uptime - startedUptime < 600,
              let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "deccanqueenonrails.com", parts.percentEncodedHost == "deccanqueenonrails.com", parts.port == nil,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.percentEncodedPath == "/native/attendee/ios/callback",
              let items = parts.queryItems, items.count == 2,
              items.filter({ $0.name == "state" }).count == 1, items.filter({ $0.name == "code" }).count == 1,
              let received = items.first(where: { $0.name == "state" })?.value, Self.matches(received, state),
              let code = items.first(where: { $0.name == "code" })?.value,
              NativeAttendeeAPI.opaque(code, prefix: "nac1_"), !code.contains(where: { $0.isWhitespace || $0.isNewline }), !code.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw AttendeeAuthError.invalidCallback }
        return AttendeeCodeExchange(code: code, verifier: verifier)
    }
    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for i in a.indices { difference |= a[i] ^ b[i] }
        return difference == 0
    }
}
@MainActor
final class AttendeeSessionStore: ObservableObject {
    enum Phase: Equatable { case unavailable, signedOut, authorizing, exchanging, loading, ready }
    @Published private(set) var phase: Phase
    @Published private(set) var account: AttendeeAccount?
    @Published private(set) var passes: [AttendeePass] = []
    @Published private(set) var message: String?
    @Published private(set) var loading = false
    @Published private(set) var stale = false
    @Published private(set) var moreResults = false
    @Published private(set) var revocationPending = false
    @Published private(set) var checkedAt: String?
    @Published private(set) var limitReached = false
    @Published private(set) var accountCheckedAt: String?
    @Published private(set) var passObservations: [String: String] = [:]
    @Published private(set) var retryDelay = 0
    let synthetic: Bool
    let supportsHTTPSCallback: Bool
    private let api: (any AttendeeBridgeAPI)?
    private let browser: (any AttendeeBrowserAuthorizing)?
    private let now: @Sendable () -> Date
    private let uptime: @Sendable () -> TimeInterval
    private var lease: AttendeeLease?
    private var deadline: TimeInterval?
    private var acceptedUptime: TimeInterval?
    private var nextCursor: String?
    private var seenCursors = Set<String>()
    private var pending: AttendeeLoginTransaction?
    private var generation = 0
    private var task: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private let operationTimeout: TimeInterval
    private let authorizationTimeout: TimeInterval
    private var retryUptime: TimeInterval?
    private var cooldownTask: Task<Void, Never>?
    private var revocationTimeoutTask: Task<Void, Never>?
    private var revocationExpiryTask: Task<Void, Never>?
    private var revocationTask: Task<Void, Never>?
    private var revocationLease: AttendeeLease?
    private var revocationDeadline: TimeInterval?
    private var revocationGeneration = 0
    init(api: (any AttendeeBridgeAPI)? = nil, browser: (any AttendeeBrowserAuthorizing)? = nil, synthetic: Bool = false, supportsHTTPSCallback: Bool = AttendeePlatformPolicy.supportsHTTPSCallback, now: @escaping @Sendable () -> Date = { Date() }, uptime: @escaping @Sendable () -> TimeInterval = { AttendeeElapsedClock.now() }, operationTimeout: TimeInterval = 20, authorizationTimeout: TimeInterval = 600) {
        self.api = api; self.browser = browser; self.synthetic = synthetic
        self.supportsHTTPSCallback = supportsHTTPSCallback; self.now = now; self.uptime = uptime; self.operationTimeout = operationTimeout; self.authorizationTimeout = authorizationTimeout
        phase = synthetic && api != nil && browser != nil && supportsHTTPSCallback ? .signedOut : .unavailable
    }
    var canRequest: Bool { retryUptime.map { uptime() >= $0 } ?? true }
    func signIn() {
        guard canRequest, phase == .signedOut, synthetic, supportsHTTPSCallback, let api, let browser else { return }
        generation += 1
        let current = generation
        message = nil; phase = .authorizing; armTimeout(authorizationTimeout)
        task = Task {
            do {
                let transaction = try AttendeeLoginTransaction(uptime: uptime())
                pending = transaction
                let callback = try await browser.authorize(transaction.authorizeURL)
                guard current == generation, !Task.isCancelled, pending != nil else { return }
                pending = nil
                let exchange = try transaction.exchange(callback: callback, uptime: uptime())
                phase = .exchanging; armTimeout(operationTimeout)
                let result = try await api.exchange(exchange)
                guard current == generation, !Task.isCancelled else { discard(result); return }
                try accept(result)
                phase = .loading; loading = true
                try await loadInitial(api, result, generation: current)
                guard current == generation, !Task.isCancelled else { return }
                phase = .ready; loading = false; task = nil; stopTimeout()
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                let error = reason(error, fallback: phase == .exchanging ? .uncertainExchange : .offline)
                invalidate(message: error.message)
            }
        }
    }
    @discardableResult
    func receiveExternalCallback(_ url: URL) -> Bool {
        guard phase == .authorizing, supportsHTTPSCallback, synthetic || AttendeeActivation.liveEnabled, let pending, let browser,
              (try? pending.exchange(callback: url, uptime: uptime())) != nil else { return false }
        return browser.receiveExternal(url)
    }
    func cancelLogin() {
        guard phase == .authorizing || phase == .exchanging || phase == .loading else { return }
        browser?.cancel(); invalidate(message: AttendeeAuthError.canceled.message)
    }
    private func accept(_ result: AttendeeLease) throws {
        let duration = result.expiresAt.timeIntervalSince(now())
        guard NativeAttendeeAPI.opaque(result.token, prefix: "na1_"), duration > 0, duration <= 1800 else { throw AttendeeAuthError.invalidResponse }
        lease = result; acceptedUptime = uptime(); deadline = uptime() + duration
        expiryTask?.cancel()
        let current = generation
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard let self, current == self.generation, !Task.isCancelled else { return }
            self.invalidate(message: AttendeeAuthError.expired.message)
        }
    }
    private var valid: Bool {
        guard let lease, let deadline, let acceptedUptime else { return false }
        return now() < lease.expiresAt && uptime() >= acceptedUptime && uptime() < deadline
    }
    private func verified(_ schema: Int, _ event: String, _ checkedAt: String) throws {
        guard schema == 1, event == "dqor-2026", NativeAttendeeAPI.date(checkedAt) != nil else { throw AttendeeAuthError.invalidResponse }
    }
    private func verify(_ page: AttendeeAccountPage) throws {
        try verified(page.schemaVersion, page.event, page.checkedAt)
        guard Self.validCursor(page.account.id), !page.account.email.isEmpty, page.account.email.utf8.count <= 512, (page.account.name?.utf8.count ?? 0) <= 512 else { throw AttendeeAuthError.invalidResponse }
        if let account, account.id != page.account.id || account.email != page.account.email { throw AttendeeAuthError.revoked }
    }
    private func verify(_ page: AttendeePassPage) throws {
        try verified(page.schemaVersion, page.event, page.checkedAt)
        guard page.passes.count <= 20, Set(page.passes.map(\.id)).count == page.passes.count,
              page.moreResults == (page.nextCursor != nil), page.nextCursor.map({ Self.validCursor($0) }) ?? true, !page.moreResults || page.nextCursor == page.passes.last?.id else { throw AttendeeAuthError.invalidResponse }
        guard page.passes.map(\.id).compactMap(Int64.init) == page.passes.map(\.id).compactMap(Int64.init).sorted() else { throw AttendeeAuthError.invalidResponse }
        for pass in page.passes {
            guard Self.validCursor(pass.id), Self.validCursor(pass.type.id), pass.type.name.utf8.count <= 512,
                  ["confirmed", "pending", "expired", "canceled"].contains(pass.status), pass.entry.count <= 4,
                  Set(pass.entry.map(\.date)).count == pass.entry.count else { throw AttendeeAuthError.invalidResponse }
        }
    }
    nonisolated static func validCursor(_ value: String) -> Bool {
        guard !value.isEmpty, value.first != "0", value.utf8.count <= 19, value.utf8.allSatisfy({ (48...57).contains($0) }), let cursor = UInt64(value), cursor <= UInt64(Int64.max) else { return false }
        return true
    }
    private func loadInitial(_ api: any AttendeeBridgeAPI, _ lease: AttendeeLease, generation current: Int) async throws {
        armTimeout(operationTimeout)
        let info = try await api.account(lease)
        guard current == generation, !Task.isCancelled else { throw CancellationError() }
        guard valid else { throw AttendeeAuthError.expired }
        try verify(info)
        armTimeout(operationTimeout)
        let page = try await api.passes(lease, cursor: nil)
        guard current == generation, !Task.isCancelled else { throw CancellationError() }
        guard valid else { throw AttendeeAuthError.expired }
        try verify(page)
        account = info.account; accountCheckedAt = info.checkedAt; passObservations = Dictionary(uniqueKeysWithValues: page.passes.map { ($0.id, page.checkedAt) }); passes = page.passes; moreResults = page.moreResults; nextCursor = page.nextCursor
        seenCursors.removeAll(); stale = false; message = nil; checkedAt = page.checkedAt; limitReached = false
    }
    func refresh() {
        guard canRequest, phase == .ready, !loading, let api, let lease else { return }
        guard valid else { invalidate(message: AttendeeAuthError.expired.message); return }
        let current = generation
        loading = true; stale = true; armTimeout(operationTimeout)
        task = Task {
            do {
                let response = try await api.session(lease)
                guard current == generation, !Task.isCancelled else { return }
                try verified(response.schemaVersion, response.event, response.checkedAt)
                guard response.clientID == "dqor-ios", response.capabilities.sorted() == NativeAttendeeAPI.capabilities.sorted(), let expiry = NativeAttendeeAPI.date(response.expiresAt), expiry == lease.expiresAt else { throw AttendeeAuthError.invalidResponse }
                guard valid, expiry > now() else { throw AttendeeAuthError.expired }
                try await loadInitial(api, lease, generation: current)
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                handleReadError(error)
            }
            guard current == generation else { return }
            loading = false; task = nil; stopTimeout()
        }
    }
    func loadMore() {
        guard canRequest, phase == .ready, !loading, moreResults, let cursor = nextCursor, let api, let lease else { return }
        guard valid else { invalidate(message: AttendeeAuthError.expired.message); return }
        guard passes.count < 200 else { moreResults = false; nextCursor = nil; limitReached = true; return }
        guard !seenCursors.contains(cursor) else { invalidate(message: AttendeeAuthError.invalidResponse.message); return }
        let current = generation
        loading = true; stale = true; armTimeout(operationTimeout)
        task = Task {
            do {
                let page = try await api.passes(lease, cursor: cursor)
                guard current == generation, !Task.isCancelled else { return }
                guard valid else { throw AttendeeAuthError.expired }
                try verify(page)
                guard Set(passes.map(\.id)).isDisjoint(with: Set(page.passes.map(\.id))), page.nextCursor != cursor, page.passes.first.map({ (Int64($0.id) ?? 0) > (Int64(cursor) ?? 0) }) ?? true else { throw AttendeeAuthError.invalidResponse }
                if passes.count + page.passes.count > 200 {
                    moreResults = false; nextCursor = nil; limitReached = true; stale = false; message = nil
                } else {
                    for pass in page.passes { passObservations[pass.id] = page.checkedAt }
                    passes += page.passes; seenCursors.insert(cursor); nextCursor = page.nextCursor; moreResults = page.moreResults; stale = false; message = nil; checkedAt = page.checkedAt
                }
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                handleReadError(error)
            }
            guard current == generation else { return }
            loading = false; task = nil; stopTimeout()
        }
    }
    private func handleReadError(_ error: Error) {
        let reason = reason(error, fallback: .offline)
        if !valid || reason == .expired || reason == .revoked || reason == .invalidResponse {
            invalidate(message: (!valid ? AttendeeAuthError.expired : reason).message)
        } else { stale = true; message = reason.message }
    }
    func foreground() {
        if canRequest { retryUptime = nil; retryDelay = 0 }
        if lease != nil && !valid { invalidate(message: AttendeeAuthError.expired.message) }
        else if phase == .ready { refresh() }
        if let revocationLease, now() >= revocationLease.expiresAt || uptime() >= (revocationDeadline ?? 0) { expireRevocation() }
    }
    func logout() {
        let previous = lease
        let previousDeadline = deadline
        browser?.cancel(); invalidate(message: "Signed out on this device.")
        guard let previous else { return }
        revocationTask?.cancel(); revocationTask = nil; revocationGeneration += 1
        revocationLease = previous; revocationDeadline = previousDeadline; revocationPending = true; armRevocationExpiry(); retryRevocation()
    }
    func retryRevocation() {
        guard revocationTask == nil, let previous = revocationLease, let api else { return }
        guard now() < previous.expiresAt, uptime() < (revocationDeadline ?? 0) else { expireRevocation(); return }
        let current = revocationGeneration
        revocationTimeoutTask?.cancel()
        revocationTimeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(self?.operationTimeout ?? 20)) } catch { return }
            guard let self, current == self.revocationGeneration else { return }
            self.revocationGeneration += 1; self.revocationTask?.cancel(); self.revocationTask = nil; self.revocationPending = true; self.armRevocationExpiry()
        }
        revocationTask = Task {
            do {
                try await api.revoke(previous)
                guard current == revocationGeneration else { return }
                revocationLease = nil; revocationPending = false; revocationDeadline = nil; revocationExpiryTask?.cancel(); revocationExpiryTask = nil
            } catch {
                guard current == revocationGeneration else { return }
                if (error as? AttendeeServiceFailure)?.code == .unauthenticated || error as? AttendeeAuthError == .revoked {
                    revocationLease = nil; revocationPending = false; revocationDeadline = nil; revocationExpiryTask?.cancel(); revocationExpiryTask = nil
                    message = "The previous session is already unavailable."
                } else { revocationPending = true }
            }
            guard current == revocationGeneration else { return }
            revocationTask = nil; revocationTimeoutTask?.cancel(); revocationTimeoutTask = nil
        }
    }
    private func discard(_ result: AttendeeLease) {
        guard NativeAttendeeAPI.opaque(result.token, prefix: "na1_"), result.expiresAt > now(), result.expiresAt.timeIntervalSince(now()) <= 1800, revocationLease == nil else { return }
        revocationLease = result; revocationDeadline = uptime() + result.expiresAt.timeIntervalSince(now()); revocationPending = true; armRevocationExpiry(); retryRevocation()
    }
    private func armRevocationExpiry() {
        revocationExpiryTask?.cancel()
        guard let revocationLease, let revocationDeadline else { return }
        let remaining = min(revocationLease.expiresAt.timeIntervalSince(now()), revocationDeadline - uptime())
        guard remaining > 0 else { expireRevocation(); return }
        let current = revocationGeneration
        revocationExpiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard let self, current == self.revocationGeneration, !Task.isCancelled else { return }
            self.expireRevocation()
        }
    }
    private func expireRevocation() {
        revocationGeneration += 1; revocationTask?.cancel(); revocationTask = nil
        revocationTimeoutTask?.cancel(); revocationTimeoutTask = nil
        revocationExpiryTask?.cancel(); revocationExpiryTask = nil
        revocationLease = nil; revocationDeadline = nil; revocationPending = false
    }
    private func reason(_ error: Error, fallback: AttendeeAuthError) -> AttendeeAuthError {
        if let failure = error as? AttendeeServiceFailure {
            if let delay = failure.retryAfter {
                retryUptime = uptime() + Double(delay); retryDelay = delay; cooldownTask?.cancel()
                cooldownTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    self?.retryUptime = nil; self?.retryDelay = 0
                }
            }
            return failure.reason
        }
        return error as? AttendeeAuthError ?? fallback
    }
    private func invalidate(message: String?) {
        generation += 1; task?.cancel(); task = nil; pending = nil; stopTimeout(); expiryTask?.cancel(); expiryTask = nil
        lease = nil; deadline = nil; acceptedUptime = nil; account = nil; accountCheckedAt = nil; passObservations = [:]; passes = []; nextCursor = nil; seenCursors.removeAll()
        moreResults = false; loading = false; stale = false; checkedAt = nil; limitReached = false; self.message = message
        phase = synthetic && supportsHTTPSCallback ? .signedOut : .unavailable
    }
    private func armTimeout(_ seconds: TimeInterval) {
        timeoutTask?.cancel()
        let current = generation
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, current == self.generation, !Task.isCancelled else { return }
            let reason: AttendeeAuthError = self.phase == .exchanging ? .uncertainExchange : .offline
            self.browser?.cancel(); self.invalidate(message: reason.message)
        }
    }
    private func stopTimeout() { timeoutTask?.cancel(); timeoutTask = nil }
    deinit { revocationExpiryTask?.cancel(); expiryTask?.cancel(); task?.cancel(); timeoutTask?.cancel(); revocationTask?.cancel(); revocationTimeoutTask?.cancel(); cooldownTask?.cancel() }
}
