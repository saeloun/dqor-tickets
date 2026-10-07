#if DEBUG
import SwiftUI

actor PublicProgrammePreviewTransport: ProgrammeTransport {
    enum Scenario: String, CaseIterable {
        case published = "Published", unchanged = "Unchanged 304", offline = "Offline", unavailable = "Service unavailable", empty = "Withdraw all", slow = "Slow response"
    }
    private var scenario: Scenario = .published
    init(offline: Bool = false) { if offline { scenario = .offline } }
    func setScenario(_ value: Scenario) { scenario = value }
    func fetch(ifNoneMatch: String?) async throws -> ProgrammeResponse {
        let selected = scenario
        if selected == .slow { try await Task.sleep(for: .seconds(3)) }
        if selected == .offline { throw URLError(.notConnectedToInternet) }
        if selected == .unavailable { return ProgrammeResponse(status: 503, etag: nil, data: Data()) }
        if selected == .unchanged, ifNoneMatch == "W/\"synthetic-public\"" { return ProgrammeResponse(status: 304, etag: nil, data: Data()) }
        let sessions = selected == .empty ? "[]" : """
        [{"id":"synthetic-published","title":"Synthetic published session","abstract":"A synthetic session used to rehearse navigation and saving. It is not part of the live programme.","starts_at":"2026-10-08T09:00:00+05:30","ends_at":null,"local_date":"2026-10-08","speaker_id":null,"speaker_name":null,"room":null},{"id":"synthetic-unscheduled","title":"Synthetic unscheduled session","abstract":null,"starts_at":null,"ends_at":null,"local_date":null,"speaker_id":null,"speaker_name":null,"room":null}]
        """
        let json = """
        {"schema_version":1,"content_version":"synthetic-public","event":{"id":"synthetic-public-event","title":"Synthetic public programme","start_date":"2026-10-08","end_date":"2026-10-11","timezone":"Asia/Kolkata","venue":"Synthetic venue","public_url":"https://example.invalid"},"sessions":\(sessions),"speakers":[]}
        """
        return ProgrammeResponse(status: 200, etag: "W/\"synthetic-public\"", data: Data(json.utf8))
    }
}

struct PublicProgrammePreviewControls: View {
    @ObservedObject var store: PublicProgrammeStore
    var body: some View {
        Group {
            DQORRowCopy(text: "Offline test controls · synthetic responses", emphasized: true)
            ForEach(PublicProgrammePreviewTransport.Scenario.allCases, id: \.self) { scenario in
                Button { Task { await store.preview(scenario) } } label: {
                    DQORRowCopy(text: scenario.rawValue, emphasized: true)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(AttendeePressStyle()).disabled(store.loading)
            }
        }
    }
}
#endif
