#if DEBUG
import SwiftUI

@MainActor
final class SyntheticAttendeeBrowser: ObservableObject, AttendeeBrowserAuthorizing {
    enum ReturnKind { case approved, wrongState, wrongOrigin, duplicate }
    @Published private(set) var waiting = false
    private var completion: CheckedContinuation<URL, Error>?
    private var state: String?
    func authorize(_ url: URL) async throws -> URL {
        guard completion == nil else { throw AttendeeAuthError.invalidCallback }
        state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "state" })?.value
        waiting = true
        return try await withCheckedThrowingContinuation { completion = $0 }
    }
    func finish(_ kind: ReturnKind = .approved) {
        guard let state, let previous = completion else { return }
        var parts = URLComponents(string: kind == .wrongOrigin ? "https://example.test/native/attendee/ios/callback" : "https://deccanqueenonrails.com/native/attendee/ios/callback")!
        parts.queryItems = [URLQueryItem(name: "code", value: "nac1_" + String(repeating: "A", count: 43)), URLQueryItem(name: "state", value: kind == .wrongState ? "mismatched" : state)]
        if kind == .duplicate { parts.queryItems?.append(URLQueryItem(name: "state", value: state)) }
        completion = nil; self.state = nil; waiting = false
        previous.resume(returning: parts.url!)
    }
    func callback() -> URL? {
        guard let state else { return nil }
        var parts = URLComponents(string: "https://deccanqueenonrails.com/native/attendee/ios/callback")!
        parts.queryItems = [URLQueryItem(name: "code", value: "nac1_" + String(repeating: "A", count: 43)), URLQueryItem(name: "state", value: state)]
        return parts.url
    }
    func receiveExternal(_ url: URL) -> Bool {
        guard let previous = completion else { return false }
        completion = nil; state = nil; waiting = false; previous.resume(returning: url)
        return true
    }
    func cancel() {
        let previous = completion; completion = nil; state = nil; waiting = false
        previous?.resume(throwing: AttendeeAuthError.canceled)
    }
}

actor SyntheticAttendeeBridge: AttendeeBridgeAPI {
    enum Scenario: String, CaseIterable { case published = "Published samples", empty = "Empty samples", offline = "Offline", revoked = "Revoked", expired = "Expired", slow = "Slow response", uncertain = "Uncertain exchange" }
    private var scenario = Scenario.published
    func set(_ scenario: Scenario) { self.scenario = scenario }
    private func check() async throws {
        if scenario == .slow { try await Task.sleep(for: .seconds(3)) }
        if scenario == .offline { throw AttendeeAuthError.offline }
        if scenario == .revoked { throw AttendeeAuthError.revoked }
        if scenario == .expired { throw AttendeeAuthError.expired }
    }
    func exchange(_ exchange: AttendeeCodeExchange) async throws -> AttendeeLease {
        try await check()
        if scenario == .uncertain { throw AttendeeAuthError.uncertainExchange }
        return AttendeeLease(token: "na1_" + String(repeating: "B", count: 43), expiresAt: NativeAttendeeAPI.date(ISO8601DateFormatter().string(from: Date().addingTimeInterval(1200)))!)
    }
    private var observed: String { ISO8601DateFormatter().string(from: Date()) }
    func account(_ lease: AttendeeLease) async throws -> AttendeeAccountPage {
        try await check()
        return AttendeeAccountPage(schemaVersion: 1, event: "dqor-2026", checkedAt: observed, account: AttendeeAccount(id: "1", name: "Synthetic attendee", email: "attendee@example.test"))
    }
    func passes(_ lease: AttendeeLease, cursor: String?) async throws -> AttendeePassPage {
        try await check()
        if scenario == .empty { return AttendeePassPage(schemaVersion: 1, event: "dqor-2026", checkedAt: observed, passes: [], moreResults: false, nextCursor: nil) }
        let entries: [AttendeePass.Entry] = [.init(date: "2026-10-08", eligible: true, checkedInAt: nil), .init(date: "2026-10-09", eligible: true, checkedInAt: "2026-10-09T09:00:00+05:30")]
        let ids = cursor == nil ? ["1", "2"] : ["3", "4"]
        let states = cursor == nil ? ["confirmed", "pending"] : ["canceled", "expired"]
        let records = zip(ids, states).map { id, status in
            AttendeePass(id: id, type: .init(id: "1", name: "Synthetic conference"), status: status, admission: .init(startsOn: nil, endsOn: nil), entry: status == "confirmed" ? entries : entries.map { .init(date: $0.date, eligible: false, checkedInAt: nil) })
        }
        return AttendeePassPage(schemaVersion: 1, event: "dqor-2026", checkedAt: observed, passes: records, moreResults: cursor == nil, nextCursor: cursor == nil ? "2" : nil)
    }
    func session(_ lease: AttendeeLease) async throws -> AttendeeSessionPage { try await check(); return AttendeeSessionPage(schemaVersion: 1, event: "dqor-2026", clientID: "dqor-ios", capabilities: NativeAttendeeAPI.capabilities, expiresAt: ISO8601DateFormatter().string(from: lease.expiresAt), checkedAt: observed) }
    func revoke(_ lease: AttendeeLease) async throws { try await check() }
}
#endif
