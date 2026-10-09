import SwiftUI

@main
struct DQORStaffApp: App {
    @StateObject private var store = StaffStore(api: DemoStaffAPI(
        offline: ProcessInfo.processInfo.arguments.contains("--offline"),
        failCheckIn: ProcessInfo.processInfo.arguments.contains("--fail-checkin"),
        role: ProcessInfo.processInfo.arguments.contains("--finance") ? .finance : .volunteer,
        duplicateNames: ProcessInfo.processInfo.arguments.contains("--duplicate-names")))
    private var previewColorScheme: ColorScheme? {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--dark-preview") ? .dark : nil
        #else
        return nil
        #endif
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--demo") { StaffRootView(store: store) }
                else { PublicEventRootView(demoStore: store) }
            }.preferredColorScheme(previewColorScheme)
        }
    }
}

struct StaffRootView: View {
    @ObservedObject var store: StaffStore
    @StateObject private var agenda = AttendeeAgenda()
    @State private var query = ""
    @State private var scanning = false
    @State private var leaving = false
    @ScaledMetric(relativeTo: .body) private var cameraHeight = 280.0
    var body: some View {
        NavigationStack {
            Group {
                if store.session == nil { signIn }
                else if store.day == nil { eventPicker }
                else if !store.can(.searchAttendees) {
                    ContentUnavailableView("Check-in access unavailable", systemImage: "lock", description: Text("This demo role cannot check in attendees. Contact your event administrator for access."))
                } else { checkIn }
            }
            .navigationTitle(store.day == nil ? "DQOR Staff" : "Check-in")
            .navigationBarTitleDisplayMode(store.session == nil ? .inline : .automatic)
            .toolbar {
                if store.session != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        if let day = store.day {
                            Menu("Explore", systemImage: "ellipsis.circle") {
                                NavigationLink("Event preview") { AttendeeEventView(day: day) }
                                NavigationLink("Schedule") { EventCompanionView(day: day, wallet: false) }
                                NavigationLink("Sample passes") { EventCompanionView(day: day, wallet: true) }
                                if store.can(.searchAttendees) {
                                    NavigationLink("Activity history") { StaffHistoryView(store: store) }
                                }
                            }.disabled(store.busy).accessibilityIdentifier("exploreEvent")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button(store.day == nil ? "Sign out" : "Events") {
                            if !store.selection.isEmpty { leaving = true }
                            else { leave() }
                        }.font(.body).foregroundStyle(.primary).disabled(store.busy)
                    }
                }
            }
            .confirmationDialog("Discard this unsubmitted batch?", isPresented: $leaving, titleVisibility: .visible) {
                Button("Discard batch", role: .destructive) { leave() }
                Button("Keep batch", role: .cancel) {}
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    ScrollView { VStack(spacing: 20) {
                        CameraScanner { payload in Task { await store.scan(payload) } }
                            .frame(height: cameraHeight).accessibilityLabel("Ticket camera preview")
                        Text("Event admission · scanner rehearsal").font(.headline)
                        Text("Demo environment · no live attendance changes").font(.caption)
                        Text("\(store.selection.count) in batch").font(.title2.bold()).accessibilityAddTraits(.updatesFrequently)
                        Text(store.message ?? "Point at a ticket QR code. Attendees are added to a batch for review.")
                            .padding().accessibilityIdentifier("scanStatus")
                        Button { scanning = false } label: {
                            Text("Use attendee search").frame(minHeight: 48)
                        }.buttonStyle(.bordered).tint(AttendeeStyle.accent)
                            .foregroundStyle(Color(uiColor: .label))
                    } }.navigationTitle("Scan tickets")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { scanning = false }.font(.body) } }
                }
            }
            .sheet(isPresented: $store.confirming) {
                NavigationStack {
                    List {
                        Section(header: Text("Confirm event admission and day").foregroundStyle(Color(uiColor: .label)).font(.headline)) {
                            Text(store.day?.event ?? "").font(.headline)
                            Text(store.day?.day ?? "")
                            Text("Demo environment · no live attendance changes").font(.caption)
                        }
                        Section(header: Text("Selected attendees · \(store.selection.count)").foregroundStyle(Color(uiColor: .label)).font(.headline)) {
                            ForEach(store.selection) { attendee in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(attendee.name).font(.body)
                                    Text(attendee.email).font(.caption)
                                }.fixedSize(horizontal: false, vertical: true)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityIdentifier("review-\(attendee.id)")
                            }
                        }
                        Section {
                            Button("Confirm check-in") { Task { await store.confirm() } }
                                .buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy)
                            Text("Each attendee receives a separate result. Check-in requires a server response.").font(.caption)
                        }
                    }.navigationTitle("Review batch")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { store.confirming = false }.font(.body) } }
                }
            }
        }.environmentObject(agenda).tint(store.day?.theme.color ?? .indigo)
            .onChange(of: store.message) { _, message in
                if UIAccessibility.isVoiceOverRunning, let message {
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
            }
            .onChange(of: store.results.count) { _, count in
                if UIAccessibility.isVoiceOverRunning, count > 0 {
                    UIAccessibility.post(notification: .announcement, argument: "Batch processed. Review each attendee result.")
                }
            }
    }
    private func leave() {
        query = ""
        if store.day == nil { Task { await store.signOut() } }
        else { store.clearDay() }
    }
    private var signIn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("DQOR").font(.title3.weight(.bold)).tracking(2)
                    Spacer()
                    Button("Staff demo") { Task { await store.signIn() } }
                        .font(.body).frame(minHeight: 48)
                        .fixedSize(horizontal: false, vertical: true)
                        .buttonStyle(.bordered).disabled(store.busy)
                        .accessibilityIdentifier("staffDemoShortcut")
                }
                Text("Good company.\nGreat possibilities.")
                    .font(.system(.largeTitle, design: .serif).weight(.medium))
                Text("A place for the moments that bring us together.")
                    .font(.body).foregroundStyle(AttendeeStyle.secondary)
                PreviewBadge()
                NavigationLink { AttendeeEventView(day: DemoCompanion.previewDay) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        EventArtwork(showsHeadline: false).aspectRatio(1.25, contentMode: .fit)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 16) {
                            AttendeeEventTitle(day: DemoCompanion.previewDay)
                            HStack {
                                Text("Explore sample event").font(.headline)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.frame(minHeight: 48)
                        }.padding(24)
                    }.background(AttendeeStyle.card, in: RoundedRectangle(cornerRadius: 24))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                }.buttonStyle(AttendeePressStyle()).accessibilityIdentifier("exploreSampleEvent")
                Text("14 November 2026 · Pune").font(.subheadline)
                    .foregroundStyle(AttendeeStyle.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 16) {
                    Label("For the welcome desk", systemImage: "qrcode.viewfinder").font(.headline)
                    Text("Scan sample tickets, review a batch, and confirm every arrival in the staff demo.")
                        .font(.body).foregroundStyle(AttendeeStyle.secondary)
                    Label("Demo mode · synthetic attendees only", systemImage: "testtube.2")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Button("Enter demo") { Task { await store.signIn() } }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy)
                        .accessibilityIdentifier("enterDemo")
                    if let message = store.message { Text(message).foregroundStyle(.red) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AttendeeStyle.card, in: RoundedRectangle(cornerRadius: 20))
                Text("This native preview uses fictional content. Registration, live passes, and attendance are not connected.")
                    .font(.footnote).foregroundStyle(AttendeeStyle.secondary)
            }.padding(24).frame(maxWidth: 640).modifier(AttendeeReveal())
        }.frame(maxWidth: .infinity).background(AttendeeStyle.canvas)
            .foregroundStyle(AttendeeStyle.ink).tint(AttendeeStyle.accent)
    }
    private var eventPicker: some View {
        List {
            Section { Text("Demo environment").foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true) }
            Section(header: Text("Choose an event and day").foregroundStyle(Color(uiColor: .label)).font(.headline)) {
                ForEach(store.days) { day in
                    Button { store.choose(day) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "calendar").font(.title2).foregroundStyle(day.theme.color).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) { Text(day.event).font(.headline).foregroundStyle(Color.primary); Text(day.day).foregroundStyle(Color.primary) }
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
                Text(store.day?.day ?? "").foregroundStyle(.primary)
                Text("Demo · no live check-ins").font(.caption).fixedSize(horizontal: false, vertical: true)
                Button { store.message = nil; scanning = true } label: { Text("Scan tickets").fixedSize(horizontal: false, vertical: true) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy || !store.can(.scanTickets))
            }
            Section(header: Text("Find attendees").foregroundStyle(Color(uiColor: .label)).font(.headline)) {
                Text("Name, email, or ticket ID").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                TextField("Search", text: $query)
                    .accessibilityLabel("Name, email, or ticket ID")
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .accessibilityIdentifier("attendeeSearch")
                    .onSubmit { Task { await store.search(query) } }
                Button("Search attendees") { Task { await store.search(query) } }.disabled(store.busy)
                ForEach(store.matches) { attendee in
                    Button { store.toggle(attendee) } label: {
                        HStack {
                            VStack(alignment: .leading) { Text(attendee.name).foregroundStyle(.primary); Text(attendee.email).font(.caption).foregroundStyle(.primary) }.fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Image(systemName: store.selection.contains(where: { $0.id == attendee.id }) ? "checkmark.circle.fill" : "circle")
                        }.frame(minHeight: 44)
                    }.disabled(store.busy || !store.can(.checkIn)).accessibilityLabel("\(attendee.name), \(attendee.email)")
                        .accessibilityValue(store.selection.contains(where: { $0.id == attendee.id }) ? "Selected" : "Not selected")
                        .accessibilityHint("Double-tap to change batch selection")
                        .accessibilityAddTraits(store.selection.contains(where: { $0.id == attendee.id }) ? .isSelected : [])
                        .accessibilityIdentifier(attendee.id)
                }
            }
            if !store.selection.isEmpty {
                Section(header: Text("Batch · \(store.selection.count) selected").foregroundStyle(Color(uiColor: .label)).font(.headline)) {
                    ForEach(store.selection) { attendee in
                        HStack { VStack(alignment: .leading) { Text(attendee.name); Text(attendee.email).font(.caption) }.fixedSize(horizontal: false, vertical: true); Spacer(); Button("Remove") { store.toggle(attendee) }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Remove \(attendee.name), \(attendee.email)") }.disabled(store.busy)
                    }
                    Button("Review check-in") { store.confirming = true }.disabled(store.busy).accessibilityIdentifier("reviewBatch")
                    Button("Clear batch", role: .destructive) { store.cancelBatch() }.disabled(store.busy)
                }
            }
            if store.busy { ProgressView("Working…") }
            if let message = store.message { Section(header: Text("Status").foregroundStyle(Color(uiColor: .label)).font(.headline)) { Text(message).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("statusMessage") } }
            if !store.results.isEmpty {
                Section(header: Text("Last batch results").foregroundStyle(Color(uiColor: .label)).font(.headline)) {
                    ForEach(store.results) { result in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.attendee.name).font(.headline)
                            Text(result.attendee.email).font(.caption)
                            Label(result.outcome.label, systemImage: result.outcome == .checkedIn ? "checkmark.circle" : "exclamationmark.circle")
                                .foregroundStyle(.primary)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
        }.scrollDismissesKeyboard(.interactively)
    }
}

private extension EventTheme {
    var color: Color {
        switch self { case .indigo: .indigo; case .forest: Color(uiColor: .init { $0.userInterfaceStyle == .dark ? .systemGreen : UIColor(red: 0.05, green: 0.38, blue: 0.22, alpha: 1) }); case .ember: Color(uiColor: .init { $0.userInterfaceStyle == .dark ? .systemOrange : UIColor(red: 0.62, green: 0.24, blue: 0.03, alpha: 1) }) }
    }
}
