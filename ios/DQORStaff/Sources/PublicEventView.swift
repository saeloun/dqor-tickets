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
                guard !Task.isCancelled, requestGeneration == generation else { return }
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
        let clearGeneration = generation
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
        guard clearGeneration == generation else { return }
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

private enum DQORTab: Hashable { case home, programme, pass, you }

struct PublicEventRootView: View {
    @ObservedObject var demoStore: StaffStore
    @StateObject private var programme: PublicProgrammeStore
    @StateObject private var attendee: AttendeeSessionStore
    #if DEBUG
    private let attendeeBrowser: SyntheticAttendeeBrowser?
    private let attendeeAPI: SyntheticAttendeeBridge?
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var clearing = false
    @State private var selectedTab: DQORTab = .home
    init(demoStore: StaffStore) {
        self.demoStore = demoStore
        #if DEBUG
        let fixture = ProcessInfo.processInfo.arguments.contains("--public-fixture")
        let authFixture = ProcessInfo.processInfo.arguments.contains("--attendee-auth-fixture")
        let browser = authFixture ? SyntheticAttendeeBrowser() : nil
        let api = authFixture ? SyntheticAttendeeBridge() : nil
        attendeeBrowser = browser; attendeeAPI = api
        _attendee = StateObject(wrappedValue: AttendeeSessionStore(api: api, browser: browser, synthetic: authFixture, supportsHTTPSCallback: ProcessInfo.processInfo.arguments.contains("--attendee-older-policy") ? false : AttendeePlatformPolicy.supportsHTTPSCallback))
        _programme = StateObject(wrappedValue: fixture ? PublicProgrammeStore(transport: PublicProgrammePreviewTransport(offline: ProcessInfo.processInfo.arguments.contains("--public-offline")), isFixture: true) : PublicProgrammeStore())
        #else
        _attendee = StateObject(wrappedValue: AttendeeSessionStore())
        _programme = StateObject(wrappedValue: PublicProgrammeStore())
        #endif
    }
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { home }
                .tabItem { Label("Home", systemImage: "house") }.tag(DQORTab.home)
            NavigationStack {
                PublicScheduleView(store: programme).toolbar { homeToolbar }
            }.tabItem { Label("Programme", systemImage: "calendar") }.tag(DQORTab.programme)
            NavigationStack {
                DQORPassView(store: attendee) { selectedTab = .you }.toolbar { homeToolbar }
            }.tabItem { Label("Pass", systemImage: "ticket") }.tag(DQORTab.pass)
            NavigationStack { attendeeAccount.toolbar { homeToolbar } }
                .tabItem { Label("You", systemImage: "person.crop.circle") }.tag(DQORTab.you)
        }.tint(DQORStyle.ink)
            .toolbarBackground(DQORStyle.canvas, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .onOpenURL { attendee.receiveExternalCallback($0) }
            .task { programme.refresh(automatic: true) }
            .onChange(of: selectedTab) { old, new in
                if old == .you && new != .you { attendee.cancelLogin() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { programme.refresh(automatic: true); attendee.foreground() }
            }
            .overlay {
                if scenePhase != .active && attendee.phase == .ready {
                    DQORStyle.canvas.overlay { Label("Private information hidden", systemImage: "lock").font(.headline).padding() }.ignoresSafeArea()
                }
            }
            .alert("Clear the programme and saved sessions on this device?", isPresented: $clearing) {
                Button("Clear local data", role: .destructive) { Task { await programme.clear() } }
                Button("Cancel", role: .cancel) {}
            }
            #if DEBUG
            .environment(\.openURL, OpenURLAction { url in
                ProcessInfo.processInfo.arguments.contains("--website-action-failure") ? .discarded : .systemAction(url)
            })
            #endif
    }
    private var home: some View {
        List {
            Group {
                DQORRowCopy(text: "Make room\nfor the unexpected.", emphasized: true, size: .largeTitle)
                    .fixedSize(horizontal: false, vertical: true)
                DQORRowCopy(text: "Your event, all in one place.", size: .body)
                Button { selectedTab = .programme } label: { DQORHero() }
                    .buttonStyle(AttendeePressStyle()).accessibilityIdentifier("homeHeroProgramme")
                    .accessibilityLabel("Explore the DQOR programme")
                PublicProgrammeStatus(store: programme)
                if let snapshot = programme.snapshot {
                    VStack(alignment: .leading, spacing: 8) {
                        DQORRowCopy(text: snapshot.event.title, emphasized: true).accessibilityIdentifier("publicEventTitle")
                        DQORRowCopy(text: "\(PublicProgrammeFormatting.date(snapshot.event.startDate, timezone: snapshot.event.timezone)) – \(PublicProgrammeFormatting.date(snapshot.event.endDate, timezone: snapshot.event.timezone))", size: .body)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "mappin.and.ellipse").accessibilityHidden(true)
                            DQORRowCopy(text: snapshot.event.venue, size: .body)
                        }.foregroundStyle(DQORStyle.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                    DQORRowCopy(text: "Your next move", emphasized: true, size: .title)
                    Button { selectedTab = .programme } label: {
                        DQORActionRow(title: "Programme", detail: "Sessions, times and saved talks.", symbol: "calendar")
                    }.buttonStyle(AttendeePressStyle()).accessibilityIdentifier("publicSchedule")
                } else if !programme.loading {
                    ContentUnavailableView(programme.cleared ? "Your local programme is cleared" : "Programme unavailable", systemImage: programme.cleared ? "checkmark.shield" : "wifi.exclamationmark", description: Text(programme.cleared ? "Load the public programme when you’re ready. Saved sessions have also been removed." : "The published programme will appear when a connection is available."))
                }
                Button { selectedTab = .pass } label: {
                    DQORActionRow(title: "Your pass", detail: "Keep actual ticket access close.", symbol: "ticket")
                }.buttonStyle(AttendeePressStyle()).accessibilityIdentifier("homePass")
                Button { selectedTab = .you } label: {
                    DQORActionRow(title: "Your account", detail: "Profile, privacy and preferences.", symbol: "person.crop.circle")
                }.buttonStyle(AttendeePressStyle()).accessibilityIdentifier("attendeeAccount")
                refreshButton.buttonStyle(DQORPrimaryButtonStyle())
                DQORWebsiteAction(destination: .tickets, identifier: "officialTickets")
                Divider()
                Button(role: .destructive) { clearing = true } label: {
                    DQORRowCopy(text: "Clear local programme & saved sessions", size: .body)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(AttendeePressStyle()).disabled(programme.loading && programme.cleared)
                    .accessibilityIdentifier("clearPublicProgramme")
                DQORRowCopy(text: "Saved sessions stay on this device until cleared or withdrawn. Clearing them does not sign you out of a website or change your tickets.", size: .footnote)
                NavigationLink { StaffRootView(store: demoStore) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "testtube.2").accessibilityHidden(true)
                        DQORRowCopy(text: "Open offline staff & design demo", emphasized: true)
                    }.frame(minHeight: 48)
                }.accessibilityIdentifier("offlineDemo")
                DQORRowCopy(text: "The demo uses fictional attendees and passes. It cannot change live attendance.", size: .footnote)
                #if DEBUG
                if programme.isFixture { PublicProgrammePreviewControls(store: programme) }
                #endif
            }.modifier(DQORListRows())
        }.modifier(DQORListAppearance()).modifier(AttendeeReveal())
            .navigationTitle("DQOR").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { selectedTab = .you } label: { Label("Your account", systemImage: "person.crop.circle") }
                        .accessibilityIdentifier("homeAccountToolbar")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { clearing = true } label: { Label("Clear local programme and saved sessions", systemImage: "trash") }
                        .disabled(programme.loading && programme.cleared).accessibilityIdentifier("clearPublicProgrammeToolbar")
                }
            }
    }
    @ToolbarContentBuilder
    private var homeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { selectedTab = .home } label: { Label("Home", systemImage: "chevron.left") }
                .accessibilityIdentifier("BackButton")
        }
    }
    @ViewBuilder
    private var attendeeAccount: some View {
        #if DEBUG
        AttendeeAccountView(store: attendee, previewBrowser: attendeeBrowser, previewAPI: attendeeAPI)
        #else
        AttendeeAccountView(store: attendee)
        #endif
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
                Text("Programme revalidated").font(.caption).foregroundStyle(DQORStyle.secondary)
                    .accessibilityIdentifier("programmeFresh")
            }
        }.fixedSize(horizontal: false, vertical: true).padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DQORStyle.card, in: RoundedRectangle(cornerRadius: 12))
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
    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasFilters: Bool { savedOnly || !date.isEmpty || !normalizedQuery.isEmpty }
    private var sessions: [PublicProgramme.Session] {
        (store.snapshot?.sessions ?? []).filter {
            (!savedOnly || store.savedIDs.contains($0.id)) && (date.isEmpty || $0.localDate == date) &&
            (normalizedQuery.isEmpty || [$0.title, $0.abstract ?? "", $0.speakerName ?? "", $0.room ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(normalizedQuery))
        }
    }
    private var dates: [String] { Set(store.snapshot?.sessions.compactMap(\.localDate) ?? []).sorted() }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                PublicProgrammeStatus(store: store)
                if let snapshot = store.snapshot {
                    Text(snapshot.event.title).font(.system(.title2, design: .default).weight(.medium))
                    Text("Times in \(snapshot.event.timezone)").font(.subheadline).foregroundStyle(DQORStyle.secondary)
                    Picker("Schedule view", selection: $savedOnly) {
                        Text("All sessions").tag(false)
                        Text("Saved").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("publicScheduleFilter")
                    Picker("Programme day", selection: $date) {
                        Text("All days").tag("")
                        ForEach(dates, id: \.self) { value in Text(PublicProgrammeFormatting.date(value, timezone: snapshot.event.timezone)).tag(value) }
                    }.pickerStyle(.menu).accessibilityIdentifier("publicDayFilter")
                    Text("Find a session or speaker").font(.subheadline).foregroundStyle(DQORStyle.secondary)
                    TextField("Search programme", text: $query).textFieldStyle(.roundedBorder).focused($searching)
                        .accessibilityLabel("Find a session or speaker")
                        .onSubmit { searching = false }
                        .submitLabel(.search).accessibilityIdentifier("publicProgrammeSearch")
                    if !query.isEmpty {
                        Button { query = ""; searching = false } label: {
                            Label("Clear search", systemImage: "xmark.circle").frame(minHeight: 48)
                        }.buttonStyle(.bordered).accessibilityIdentifier("publicClearSearch")
                    }
                    if sessions.isEmpty {
                        let emptySaved = savedOnly && normalizedQuery.isEmpty && date.isEmpty
                        ContentUnavailableView(snapshot.sessions.isEmpty ? "No sessions published" : emptySaved ? "Your programme, your way" : "No matching sessions", systemImage: snapshot.sessions.isEmpty ? "calendar" : "bookmark", description: Text(snapshot.sessions.isEmpty ? "Published sessions will appear here after a refresh." : emptySaved ? "Save a session to find it here. Your saved choices stay on this device." : "Try another search or programme day."))
                        if hasFilters && !snapshot.sessions.isEmpty {
                            Button { savedOnly = false; date = ""; query = ""; searching = false } label: {
                                Text(emptySaved ? "Explore all sessions" : "Reset filters").frame(minHeight: 48)
                            }.buttonStyle(.bordered).accessibilityIdentifier("publicResetFilters")
                        }
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
                    .font(.footnote).foregroundStyle(DQORStyle.secondary)
            }.padding(24).frame(maxWidth: 640)
        }.frame(maxWidth: .infinity).background(DQORStyle.canvas).foregroundStyle(DQORStyle.ink)
            .tint(DQORStyle.accent).navigationTitle("Programme").navigationBarTitleDisplayMode(.inline)
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
                    if let date = session.localDate { Text(PublicProgrammeFormatting.date(date, timezone: timezone)).font(.caption).foregroundStyle(DQORStyle.secondary) }
                    Text(PublicProgrammeFormatting.times(session, timezone: timezone)).font(.subheadline.monospacedDigit()).foregroundStyle(DQORStyle.secondary)
                    Text(session.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if let speaker = session.speakerName, !speaker.isEmpty { Text(speaker).font(.subheadline) }
                    if let room = session.room, !room.isEmpty { Label(room, systemImage: "mappin").font(.subheadline) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(action: toggle) {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark").font(.title3).frame(width: 48, height: 48)
                        .background(DQORStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(AttendeePressStyle()).accessibilityLabel(saved ? "Remove \(session.title) from saved sessions" : "Save \(session.title)")
                    .accessibilityValue(saved ? "Saved" : "Not saved").accessibilityIdentifier("publicSave-" + session.id)
            }
            if let abstract = session.abstract, !abstract.isEmpty {
                Button(expanded ? "Hide session details" : "Read session details") {
                    withAnimation(AttendeeMotion.reduced(reduceMotion) ? nil : AttendeeMotion.feedback) { expanded.toggle() }
                }.frame(minHeight: 48).accessibilityIdentifier("publicDetails-" + session.id)
                if expanded { Text(abstract).font(.body).foregroundStyle(DQORStyle.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }.padding(24).background(DQORStyle.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DQORStyle.border.opacity(0.5), lineWidth: 1))
    }
}
