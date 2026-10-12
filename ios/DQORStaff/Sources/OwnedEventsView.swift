import SwiftUI

@MainActor
final class OwnedEventsStore: ObservableObject {
    @Published private(set) var catalog = OwnedEventsClient.State()
    @Published private(set) var detail = OwnedEventsClient.State()
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    @Published var page = 1
    @Published var selectedID: String?
    let client: OwnedEventsClient
    private var task: Task<Void, Never>?
    private var invalidation: Task<Void, Never>?
    private var generation = 0
    private var cleared = false
    init(transport: any OwnedEventsTransport) { client = OwnedEventsClient(transport: transport) }
    func refresh(detail id: String? = nil) {
        generation += 1
        task?.cancel()
        loading = true
        cleared = false
        let current = generation
        let barrier = invalidation
        let resource: OwnedEventsResource = id.map { .detail($0) } ?? .catalog(page)
        task = Task {
            await barrier?.value
            guard !Task.isCancelled, current == generation else { return }
            await client.cancelPending()
            guard !Task.isCancelled, current == generation else { return }
            do {
                let next = try await client.refresh(resource)
                let catalogState = id == nil ? next : await client.state(.catalog(page))
                guard !Task.isCancelled, current == generation else { return }
                if id == nil { catalog = next } else { detail = next; catalog = catalogState }
                message = nil
            } catch {
                let state = await client.state(resource)
                guard !Task.isCancelled, current == generation else { return }
                if id == nil { catalog = state } else { detail = state }
                message = error as? OwnedEventsError == .unsupportedSchema ? "These events need a newer app version." : "Events could not be refreshed. Try again."
            }
            guard current == generation else { return }
            loading = false
            task = nil
        }
    }
    func select(_ id: String) {
        selectedID = id
        detail = OwnedEventsClient.State()
        refresh(detail: id)
    }
    func closeDetail() {
        selectedID = nil
        if !cleared { refresh() }
    }
    func move(_ amount: Int) { guard !loading else { return }; page = min(1000, max(1, page + amount)); catalog = OwnedEventsClient.State(); refresh() }
    func clear() {
        generation += 1
        task?.cancel(); task = nil
        cleared = true
        catalog = OwnedEventsClient.State(); detail = OwnedEventsClient.State()
        loading = false; message = "Your local events are cleared."
        let prior = invalidation
        invalidation = Task { await prior?.value; await client.clear() }
    }
    func background() {
        generation += 1
        task?.cancel(); task = nil; loading = false
        catalog.stale = true; detail.stale = true
        let prior = invalidation
        invalidation = Task { await prior?.value; await client.markStale() }
    }
    func foreground() { if !cleared { refresh(detail: selectedID) } }

    deinit { task?.cancel() }
}

struct OwnedEventsRootView: View {
    @StateObject private var store: OwnedEventsStore
    @Environment(\.scenePhase) private var phase
    #if DEBUG
    private let preview: OwnedEventsPreviewTransport?
    #endif
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--owned-events-fixture") {
            let fixture = OwnedEventsPreviewTransport()
            preview = fixture
            _store = StateObject(wrappedValue: OwnedEventsStore(transport: fixture))
        } else {
            preview = nil
            _store = StateObject(wrappedValue: OwnedEventsStore(transport: OwnedEventsHTTPTransport()))
        }
        #else
        _store = StateObject(wrappedValue: OwnedEventsStore(transport: OwnedEventsHTTPTransport()))
        #endif
    }
    var body: some View {
        NavigationStack {
            List {
                #if DEBUG
                if preview != nil { Text("Preview · synthetic events").accessibilityIdentifier("ownedPreview") }
                #endif
                status(store.catalog)
                if let catalog = store.catalog.catalog {
                    if catalog.events.isEmpty { Text("No events published").accessibilityIdentifier("ownedEmpty") }
                    ForEach(catalog.events) { event in
                        NavigationLink(value: event.id) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(event.title).font(.headline)
                                Text(event.organizer.name)
                                Text(event.startDate + " · " + event.timezone).font(.subheadline)
                            }.padding(.vertical, 8).fixedSize(horizontal: false, vertical: true)
                        }.accessibilityIdentifier(event.id)
                    }
                    HStack {
                        Button("Previous") { store.move(-1) }.disabled(store.page <= 1 || store.loading)
                        Spacer()
                        Text("Page \(store.page)")
                        Spacer()
                        Button("Next") { store.move(1) }.disabled(store.page >= 1000 || store.page * 24 >= catalog.pagination.total || store.loading)
                    }
                }
                Button("Refresh events") { store.refresh() }.disabled(store.loading).accessibilityIdentifier("ownedRefresh")
                Button("Clear local events", role: .destructive) { store.clear() }.accessibilityIdentifier("ownedClear")
                #if DEBUG
                if let preview { previewControls(preview) }
                #endif
            }.navigationTitle("Events")
                .navigationDestination(for: String.self) { id in detail(id) }
                .task { store.refresh() }
                .onChange(of: phase) { _, phase in
                    if phase == .background { store.background() }
                    else if phase == .active { store.foreground() }
                }
        }
    }
    @ViewBuilder private func status(_ state: OwnedEventsClient.State) -> some View {
        if store.loading { ProgressView("Refreshing events…") }
        if !state.stale && !state.unavailable && (state.catalog != nil || state.event != nil) { Text("Events up to date").accessibilityIdentifier("ownedFresh") }
        if let message = store.message { Text(message).accessibilityIdentifier("ownedProblem") }
        if state.unavailable { Text("Event information is no longer available").accessibilityIdentifier("ownedWithdrawn") }
        if state.stale && (state.catalog != nil || state.event != nil) { Text("Saved information · may be outdated").accessibilityIdentifier("ownedStale") }
    }
    private func detail(_ id: String) -> some View {
        List {
            #if DEBUG
            if preview != nil { Text("Preview · synthetic events").accessibilityIdentifier("ownedPreview") }
            #endif
            status(store.detail)
            if let event = store.detail.event {
                Text(event.title).font(.title2.bold()).accessibilityIdentifier("ownedTitle")
                Text(event.organizer.name)
                Text((PublicProgrammeFormatting.time(event.startsAt, timezone: event.timezone) ?? event.startsAt) + " – " + (PublicProgrammeFormatting.time(event.endsAt, timezone: event.timezone) ?? event.endsAt)).accessibilityIdentifier("ownedTimeRange")
                Text(event.startDate + " – " + event.endDate)
                Text(event.timezone)
                Link("View event website", destination: event.website).accessibilityIdentifier("ownedWebsite")
            }
            Button("Refresh event") { store.refresh(detail: id) }.disabled(store.loading).accessibilityIdentifier("ownedDetailRefresh")
            #if DEBUG
            if let preview { previewControls(preview, id: id) }
            #endif
        }.navigationTitle("Event details").task(id: id) { store.select(id) }.onDisappear { store.closeDetail() }
    }
    #if DEBUG
    private func previewControls(_ transport: OwnedEventsPreviewTransport, id: String? = nil) -> some View {
        Section("Preview scenarios") {
            ForEach([200, 503, 304, 404], id: \.self) { status in
                Button([200: "Published", 503: "Service unavailable", 304: "Unchanged", 404: "Withdraw event"][status]!) {
                    Task { await transport.setStatus(status); store.refresh(detail: id) }
                }.disabled(store.loading)
            }
        }
    }
    #endif
}

#if DEBUG
actor OwnedEventsPreviewTransport: OwnedEventsTransport {
    private var status = 200
    func setStatus(_ value: Int) { status = value }
    func fetch(_ resource: OwnedEventsResource, ifNoneMatch: String?) async throws -> OwnedEventsResponse {
        let data: Data
        switch resource {
        case .catalog: data = Self.catalog
        case .detail: data = Self.detail
        }
        return OwnedEventsResponse(status: status, etag: status == 404 || status == 503 ? nil : "W/\"owned-preview\"", data: status == 200 ? data : Data())
    }
    static let catalog = Data(OwnedEventsFixture.catalog.utf8)
    static let detail = Data(OwnedEventsFixture.detail.utf8)
}
#endif
