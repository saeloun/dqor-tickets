import SwiftUI

@MainActor
final class PublicProgrammeStore: ObservableObject {
    @Published private(set) var snapshot: PublicProgramme?
    @Published private(set) var isStale = false
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    @Published private(set) var savedIDs = Set<String>()
    @Published private(set) var cleared = false
    let isFixture: Bool
    private let client: PublicProgrammeClient
    private let transport: any ProgrammeTransport
    private let defaults: UserDefaults?
    static let savedKey = "dqor.public.programme.saved-session-ids.v1"
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    init(transport: any ProgrammeTransport = PublicProgrammeHTTPTransport(), isFixture: Bool = false, defaults: UserDefaults? = .standard) {
        self.defaults = isFixture ? nil : defaults
        savedIDs = Set(self.defaults?.stringArray(forKey: Self.savedKey)?.filter { !$0.isEmpty && $0.utf8.count <= 256 }.prefix(10_000) ?? [])
        self.transport = transport
        client = PublicProgrammeClient(transport: transport)
        self.isFixture = isFixture
    }
    func refresh(automatic: Bool = false) {
        guard !loading, !automatic || !cleared else { return }
        cleared = false
        loading = true
        let requestGeneration = generation
        refreshTask = Task {
            do {
                let state = try await client.refresh()
                guard !Task.isCancelled, requestGeneration == generation else { return }
                snapshot = state.snapshot
                isStale = state.isStale
                if let snapshot {
                    savedIDs.formIntersection(Set(snapshot.sessions.map(\.id)))
                    defaults?.set(savedIDs.sorted(), forKey: Self.savedKey)
                }
                message = nil
            } catch {
                guard !Task.isCancelled, requestGeneration == generation else { return }
                let state = await client.state()
                snapshot = state.snapshot
                isStale = state.isStale
                if let error = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost].contains(error.code) {
                    message = "Connection unavailable. Reconnect and try again."
                } else if error as? ProgrammeError == .unsupportedSchema {
                    message = "This programme needs a newer app version."
                } else {
                    message = "The programme is temporarily unavailable. Try again."
                }
            }
            guard requestGeneration == generation else { return }
            loading = false
            refreshTask = nil
        }
    }
    func clear() async {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        loading = true
        snapshot = nil
        savedIDs.removeAll()
        defaults?.removeObject(forKey: Self.savedKey)
        message = nil
        isStale = false
        cleared = true
        await client.clear()
        loading = false
    }
    func toggle(_ id: String) {
        guard snapshot?.sessions.contains(where: { $0.id == id }) == true else { return }
        if savedIDs.contains(id) { savedIDs.remove(id) } else { savedIDs.insert(id) }
        defaults?.set(savedIDs.sorted(), forKey: Self.savedKey)
    }
    #if DEBUG
    func preview(_ scenario: PublicProgrammePreviewTransport.Scenario) async {
        guard !loading, let preview = transport as? PublicProgrammePreviewTransport else { return }
        await preview.setScenario(scenario)
        refresh()
    }
    #endif
    deinit { refreshTask?.cancel() }
}

enum PublicProgrammeFormatting {
    static func date(_ value: String, timezone: String, format: String = "EEE, d MMM") -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        formatter.locale = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
    static func time(_ value: String?, timezone: String) -> String? {
        guard let value else { return nil }
        let parser = ISO8601DateFormatter()
        var date = parser.date(from: value)
        if date == nil { parser.formatOptions.insert(.withFractionalSeconds); date = parser.date(from: value) }
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    static func times(_ session: PublicProgramme.Session, timezone: String) -> String {
        guard let start = time(session.startsAt, timezone: timezone) else { return "Time to be announced" }
        if let end = time(session.endsAt, timezone: timezone) { return "\(start)–\(end)" }
        return start
    }
}

struct PublicEventRootView: View {
    @ObservedObject var demoStore: StaffStore
    @StateObject private var programme: PublicProgrammeStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var clearing = false
    init(demoStore: StaffStore) {
        self.demoStore = demoStore
        #if DEBUG
        let fixture = ProcessInfo.processInfo.arguments.contains("--public-fixture")
        _programme = StateObject(wrappedValue: fixture ? PublicProgrammeStore(transport: PublicProgrammePreviewTransport(offline: ProcessInfo.processInfo.arguments.contains("--public-offline")), isFixture: true) : PublicProgrammeStore())
        #else
        _programme = StateObject(wrappedValue: PublicProgrammeStore())
        #endif
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("DQOR").font(.title3.weight(.bold)).tracking(2)
                        Spacer()
                        Text("PUNE").font(.caption.weight(.semibold)).tracking(1.2)
                    }
                    if programme.snapshot != nil {
                        EventArtwork(showsHeadline: false).aspectRatio(1.25, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 24)).accessibilityHidden(true)
                    }
                    PublicProgrammeStatus(store: programme)
                    if programme.snapshot == nil { refreshButton.buttonStyle(.borderedProminent).foregroundStyle(AttendeeStyle.canvas).controlSize(.large) }
                    if let snapshot = programme.snapshot {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(snapshot.event.title).font(.system(.largeTitle, design: .serif).weight(.medium))
                                .accessibilityIdentifier("publicEventTitle")
                            Text("Good company. Great possibilities.").font(.body).foregroundStyle(AttendeeStyle.secondary)
                        }
                        Label("\(PublicProgrammeFormatting.date(snapshot.event.startDate, timezone: snapshot.event.timezone)) – \(PublicProgrammeFormatting.date(snapshot.event.endDate, timezone: snapshot.event.timezone))", systemImage: "calendar")
                        Label(snapshot.event.venue, systemImage: "mappin.and.ellipse")
                        NavigationLink { PublicScheduleView(store: programme) } label: {
                            HStack { Text("Explore the programme"); Spacer(); Image(systemName: "arrow.right") }
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                                .padding(.horizontal, 16).foregroundStyle(AttendeeStyle.canvas)
                                .background(AttendeeStyle.ink, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(AttendeePressStyle()).accessibilityIdentifier("publicSchedule")
                        refreshButton.buttonStyle(.bordered).controlSize(.large)
                    } else if !programme.loading {
                        ContentUnavailableView(programme.cleared ? "Your local programme is cleared" : "Programme unavailable", systemImage: programme.cleared ? "checkmark.shield" : "wifi.exclamationmark", description: Text(programme.cleared ? "Load the public programme when you’re ready. Saved sessions have also been removed." : "The published programme will appear when a connection is available."))
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Your tickets", systemImage: "ticket").font(.title3.weight(.semibold))
                        Text("Open your existing tickets on the official website in your browser. Native sign-in and passes are not connected.")
                            .foregroundStyle(AttendeeStyle.secondary)
                        Link(destination: URL(string: "https://deccanqueenonrails.com/tickets/mine")!) {
                            Label("Open tickets on the website", systemImage: "arrow.up.right.square").frame(minHeight: 48)
                        }.accessibilityIdentifier("officialTickets")
                        Link(destination: URL(string: "https://deccanqueenonrails.com")!) {
                            Label("Visit the event website", systemImage: "safari").frame(minHeight: 48)
                        }
                    }.padding(24).background(AttendeeStyle.card, in: RoundedRectangle(cornerRadius: 20))
                    Divider()
                    Text("A place for the moments that bring us together.").font(.system(.title2, design: .serif))
                    NavigationLink { StaffRootView(store: demoStore) } label: {
                        Label("Open offline staff & design demo", systemImage: "testtube.2").frame(minHeight: 48)
                    }.accessibilityIdentifier("offlineDemo")
                    Text("The demo contains fictional events, attendees and passes. It cannot change live attendance.")
                        .font(.footnote).foregroundStyle(AttendeeStyle.secondary)
                    Button("Clear local programme & saved sessions", role: .destructive) { clearing = true }
                        .frame(minHeight: 48).disabled(programme.loading && programme.cleared)
                        .accessibilityIdentifier("clearPublicProgramme")
                    Text("The programme stays in memory. Saved session references stay on this device until cleared or withdrawn. No account, ticket or staff data is downloaded.")
                        .font(.footnote).foregroundStyle(AttendeeStyle.secondary)
                    #if DEBUG
                    if programme.isFixture { PublicProgrammePreviewControls(store: programme) }
                    #endif
                }.padding(24).frame(maxWidth: 640).modifier(AttendeeReveal())
            }.frame(maxWidth: .infinity).background(AttendeeStyle.canvas)
                .foregroundStyle(AttendeeStyle.ink).tint(AttendeeStyle.accent)
                .navigationTitle("Deccan Queen on Rails").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { clearing = true } label: { Label("Clear local programme and saved sessions", systemImage: "trash") }
                            .disabled(programme.loading && programme.cleared).accessibilityIdentifier("clearPublicProgrammeToolbar")
                    }
                }
                .alert("Clear the programme and saved sessions on this device?", isPresented: $clearing) {
                    Button("Clear local data", role: .destructive) { Task { await programme.clear() } }
                    Button("Cancel", role: .cancel) {}
                }
                .task { programme.refresh(automatic: true) }
                .onChange(of: scenePhase) { _, phase in if phase == .active { programme.refresh(automatic: true) } }
        }
    }
    private var refreshButton: some View {
        Button(programme.snapshot == nil ? "Load programme" : "Refresh programme") { programme.refresh() }
            .frame(minHeight: 48).disabled(programme.loading)
            .accessibilityIdentifier("refreshPublicProgramme")
    }
}

struct PublicProgrammeStatus: View {
    @ObservedObject var store: PublicProgrammeStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.isFixture ? "Offline test programme · synthetic" : "Official public programme", systemImage: store.isFixture ? "testtube.2" : "checkmark.seal")
                .font(.caption.weight(.semibold))
            if store.loading { ProgressView("Refreshing programme…") }
            if store.isStale, store.snapshot != nil {
                Label("Cached programme · may be outdated", systemImage: "clock.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold)).accessibilityIdentifier("programmeStale")
            }
            if let message = store.message { Text(message).font(.subheadline).accessibilityIdentifier("programmeError") }
            if !store.loading, !store.isStale, store.snapshot != nil {
                Text("Programme revalidated").font(.caption).foregroundStyle(AttendeeStyle.secondary)
                    .accessibilityIdentifier("programmeFresh")
            }
        }.fixedSize(horizontal: false, vertical: true).padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AttendeeStyle.card, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
    }
}

struct PublicScheduleView: View {
    @ObservedObject var store: PublicProgrammeStore
    @State private var query = ""
    @State private var savedOnly = false
    @State private var date = ""
    @FocusState private var searching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var sessions: [PublicProgramme.Session] {
        (store.snapshot?.sessions ?? []).filter {
            (!savedOnly || store.savedIDs.contains($0.id)) && (date.isEmpty || $0.localDate == date) &&
            (query.isEmpty || [$0.title, $0.abstract ?? "", $0.speakerName ?? "", $0.room ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    private var dates: [String] { Set(store.snapshot?.sessions.compactMap(\.localDate) ?? []).sorted() }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                PublicProgrammeStatus(store: store)
                if let snapshot = store.snapshot {
                    Text(snapshot.event.title).font(.system(.title2, design: .serif).weight(.medium))
                    Text("Times in \(snapshot.event.timezone)").font(.subheadline).foregroundStyle(AttendeeStyle.secondary)
                    Picker("Schedule view", selection: $savedOnly) {
                        Text("All sessions").tag(false)
                        Text("Saved").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("publicScheduleFilter")
                    Picker("Programme day", selection: $date) {
                        Text("All days").tag("")
                        ForEach(dates, id: \.self) { value in Text(PublicProgrammeFormatting.date(value, timezone: snapshot.event.timezone)).tag(value) }
                    }.pickerStyle(.menu).accessibilityIdentifier("publicDayFilter")
                    Text("Find a session or speaker").font(.subheadline).foregroundStyle(AttendeeStyle.secondary)
                    TextField("Search programme", text: $query).textFieldStyle(.roundedBorder).focused($searching)
                        .accessibilityLabel("Find a session or speaker")
                        .onSubmit { searching = false }
                        .submitLabel(.search).accessibilityIdentifier("publicProgrammeSearch")
                    if sessions.isEmpty {
                        ContentUnavailableView(snapshot.sessions.isEmpty ? "No sessions published" : savedOnly && query.isEmpty ? "Your programme, your way" : "No matching sessions", systemImage: snapshot.sessions.isEmpty ? "calendar" : "bookmark", description: Text(snapshot.sessions.isEmpty ? "Published sessions will appear here after a refresh." : savedOnly && query.isEmpty ? "Save a session to find it here. Your saved choices stay on this device." : "Try another search or programme day."))
                        if savedOnly { Button("Explore all sessions") { savedOnly = false; date = ""; query = "" }.buttonStyle(.bordered).controlSize(.large) }
                    }
                    ForEach(sessions, id: \.id) { session in
                        PublicSessionCard(session: session, timezone: snapshot.event.timezone, saved: store.savedIDs.contains(session.id)) {
                            withAnimation(AttendeeMotion.reduced(reduceMotion) ? nil : AttendeeMotion.feedback) { store.toggle(session.id) }
                        }
                    }
                } else {
                    ContentUnavailableView("Programme unavailable", systemImage: "wifi.exclamationmark", description: Text("Return to the event to load the public programme."))
                }
                Button("Refresh programme") { store.refresh() }.buttonStyle(.bordered).controlSize(.large).disabled(store.loading)
                Text("Saved on this device. Refreshing removes withdrawn sessions, including saved ones.")
                    .font(.footnote).foregroundStyle(AttendeeStyle.secondary)
            }.padding(24).frame(maxWidth: 640)
        }.frame(maxWidth: .infinity).background(AttendeeStyle.canvas).foregroundStyle(AttendeeStyle.ink)
            .tint(AttendeeStyle.accent).navigationTitle("Programme").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.refresh() } label: { Label("Refresh programme", systemImage: "arrow.clockwise") }
                        .disabled(store.loading).accessibilityIdentifier("publicScheduleRefresh")
                }
            }
            .onChange(of: store.cleared) { _, cleared in if cleared { query = ""; date = ""; savedOnly = false } }
            .onChange(of: dates) { _, values in if !date.isEmpty && !values.contains(date) { date = "" } }
    }
}

private struct PublicSessionCard: View {
    let session: PublicProgramme.Session
    let timezone: String
    let saved: Bool
    let toggle: () -> Void
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    if let date = session.localDate { Text(PublicProgrammeFormatting.date(date, timezone: timezone)).font(.caption).foregroundStyle(AttendeeStyle.secondary) }
                    Text(PublicProgrammeFormatting.times(session, timezone: timezone)).font(.subheadline.monospacedDigit()).foregroundStyle(AttendeeStyle.secondary)
                    Text(session.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if let speaker = session.speakerName, !speaker.isEmpty { Text(speaker).font(.subheadline) }
                    if let room = session.room, !room.isEmpty { Label(room, systemImage: "mappin").font(.subheadline) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(action: toggle) {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark").font(.title3).frame(width: 48, height: 48)
                        .background(AttendeeStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(AttendeePressStyle()).accessibilityLabel(saved ? "Remove \(session.title) from saved sessions" : "Save \(session.title)")
                    .accessibilityValue(saved ? "Saved" : "Not saved").accessibilityIdentifier("publicSave-" + session.id)
            }
            if let abstract = session.abstract, !abstract.isEmpty {
                Button(expanded ? "Hide session details" : "Read session details") {
                    withAnimation(AttendeeMotion.reduced(reduceMotion) ? nil : AttendeeMotion.feedback) { expanded.toggle() }
                }.frame(minHeight: 48).accessibilityIdentifier("publicDetails-" + session.id)
                if expanded { Text(abstract).font(.body).foregroundStyle(AttendeeStyle.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }.padding(24).background(AttendeeStyle.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AttendeeStyle.border.opacity(0.5), lineWidth: 1))
    }
}
