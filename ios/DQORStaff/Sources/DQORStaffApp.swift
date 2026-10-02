import SwiftUI

@main
struct DQORStaffApp: App {
    @StateObject private var store = StaffStore(api: DemoStaffAPI(
        offline: ProcessInfo.processInfo.arguments.contains("--offline"),
        failCheckIn: ProcessInfo.processInfo.arguments.contains("--fail-checkin"),
        role: ProcessInfo.processInfo.arguments.contains("--finance") ? .finance : .volunteer))
    var body: some Scene { WindowGroup { StaffRootView(store: store) } }
}

struct StaffRootView: View {
    @ObservedObject var store: StaffStore
    @State private var query = ""
    @State private var scanning = false
    @State private var leaving = false
    var body: some View {
        NavigationStack {
            Group {
                if store.session == nil { signIn }
                else if store.day == nil { eventPicker }
                else if !store.can(.searchAttendees) {
                    ContentUnavailableView("Check-in access unavailable", systemImage: "lock", description: Text("This demo role has no attendance capabilities. An authorized server session must grant access."))
                } else { checkIn }
            }
            .navigationTitle(store.day == nil ? "DQOR Staff" : "Check-in")
            .toolbar {
                if store.session != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(store.day == nil ? "Sign out" : "Events") {
                            if !store.selection.isEmpty { leaving = true }
                            else { leave() }
                        }.disabled(store.busy)
                    }
                }
            }
            .confirmationDialog("Discard this unsubmitted batch?", isPresented: $leaving, titleVisibility: .visible) {
                Button("Discard batch", role: .destructive) { leave() }
                Button("Keep batch", role: .cancel) {}
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    VStack(spacing: 20) {
                        CameraScanner { payload in Task { await store.scan(payload) } }
                            .frame(minHeight: 220)
                        Text("\(store.selection.count) in batch").font(.title2.bold()).accessibilityAddTraits(.updatesFrequently)
                        Text(store.message ?? "Point at a ticket QR code. Attendees are added to a batch for review.")
                            .padding().accessibilityIdentifier("scanStatus")
                        Button("Use attendee search") { scanning = false }.buttonStyle(.bordered)
                    }.navigationTitle("Scan tickets")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { scanning = false } } }
                }
            }
            .sheet(isPresented: $store.confirming) {
                NavigationStack {
                    List {
                        Section("Confirm event and day") {
                            Text(store.day?.event ?? "").font(.headline)
                            Text(store.day?.day ?? "")
                            Text("Demo environment · no live attendance changes").font(.caption)
                        }
                        Section("Selected attendees · \(store.selection.count)") {
                            ForEach(store.selection) { attendee in Text(attendee.name) }
                        }
                        Section {
                            Button("Confirm check-in") { Task { await store.confirm() } }
                                .buttonStyle(.borderedProminent).disabled(store.busy)
                            Text("Each attendee receives a separate result. Check-in requires a server response.").font(.caption)
                        }
                    }.navigationTitle("Review batch")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { store.confirming = false } } }
                }
            }
        }.tint(store.day?.theme.color ?? .indigo)
    }
    private func leave() {
        query = ""
        if store.day == nil { Task { await store.signOut() } }
        else { store.clearDay() }
    }
    private var signIn: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "qrcode.viewfinder").font(.system(size: 54)).foregroundStyle(.indigo).accessibilityHidden(true)
            Text("Welcome your attendees.").font(.largeTitle.bold())
            Text("Scan tickets, review a batch, and confirm every arrival.").font(.title3).foregroundStyle(.secondary)
            Label("Demo mode · synthetic attendees only", systemImage: "testtube.2").font(.headline)
            Text("Explore staff check-in using sample attendees. This preview does not connect to a live event.").foregroundStyle(.secondary)
            Button("Enter demo") { Task { await store.signIn() } }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy).accessibilityIdentifier("enterDemo")
            if let message = store.message { Text(message).foregroundStyle(.red) }
        }.padding(24).frame(maxWidth: 600) }
    }
    private var eventPicker: some View {
        List {
            Section { Label("Demo environment", systemImage: "testtube.2") }
            Section("Choose an event and day") {
                ForEach(store.days) { day in
                    Button { store.choose(day) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "calendar").font(.title2).foregroundStyle(day.theme.color).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) { Text(day.event).font(.headline).foregroundStyle(Color.primary); Text(day.day).foregroundStyle(Color(uiColor: .secondaryLabel)) }
                        }
                            .padding(.vertical, 8)
                    }.accessibilityIdentifier(day.id)
                }
            }
        }
    }
    private var checkIn: some View {
        List {
            Section {
                Text(store.day?.event ?? "").font(.headline)
                Text(store.day?.day ?? "").foregroundStyle(.secondary)
                Label("Demo · no live check-ins", systemImage: "testtube.2").font(.caption)
                Button { store.message = nil; scanning = true } label: { Label("Scan tickets", systemImage: "qrcode.viewfinder") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy || !store.can(.scanTickets))
            }
            Section("Find attendees") {
                TextField("Name, email, or ticket ID", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .accessibilityIdentifier("attendeeSearch")
                    .onSubmit { Task { await store.search(query) } }
                Button("Search attendees") { Task { await store.search(query) } }.disabled(store.busy)
                ForEach(store.matches) { attendee in
                    Button { store.toggle(attendee) } label: {
                        HStack {
                            VStack(alignment: .leading) { Text(attendee.name); Text(attendee.email).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Image(systemName: store.selection.contains(where: { $0.id == attendee.id }) ? "checkmark.circle.fill" : "circle")
                        }.frame(minHeight: 44)
                    }.disabled(store.busy || !store.can(.checkIn)).accessibilityLabel("\(attendee.name), \(store.selection.contains(where: { $0.id == attendee.id }) ? "selected" : "not selected")")
                        .accessibilityIdentifier(attendee.id)
                }
            }
            if !store.selection.isEmpty {
                Section("Batch · \(store.selection.count) selected") {
                    ForEach(store.selection) { attendee in
                        HStack { Text(attendee.name); Spacer(); Button("Remove") { store.toggle(attendee) }.accessibilityLabel("Remove \(attendee.name)") }.disabled(store.busy)
                    }
                    Button("Review check-in") { store.confirming = true }.disabled(store.busy).accessibilityIdentifier("reviewBatch")
                    Button("Clear batch", role: .destructive) { store.cancelBatch() }.disabled(store.busy)
                }
            }
            if store.busy { ProgressView("Working…") }
            if let message = store.message { Section("Status") { Text(message).accessibilityIdentifier("statusMessage") } }
            if !store.results.isEmpty {
                Section("Last batch results") {
                    ForEach(store.results) { result in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.attendee.name).font(.headline)
                            Label(result.outcome.label, systemImage: result.outcome == .checkedIn ? "checkmark.circle" : "exclamationmark.circle")
                                .foregroundStyle(result.outcome == .checkedIn ? .green : .orange)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
        }.scrollDismissesKeyboard(.interactively)
    }
}

private extension EventTheme {
    var color: Color {
        switch self { case .indigo: .indigo; case .forest: .green; case .ember: .orange }
    }
}
