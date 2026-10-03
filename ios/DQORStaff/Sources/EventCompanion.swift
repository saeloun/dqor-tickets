import SwiftUI

/// Preview content is intentionally separate from staff API/session data.
struct DemoScheduleItem: Identifiable, Equatable {
    let id: String
    let time: String
    let title: String
    let location: String
}
enum DemoEntitlementStatus: String {
    case available = "Available · sample only"
    case redeemed = "Already redeemed · sample only"
    case notIncluded = "Not included"
}
struct DemoPass: Identifiable {
    let id: String
    let name: String
    let admission: DemoEntitlementStatus
    let meal: DemoEntitlementStatus
    let party: DemoEntitlementStatus
}
enum DemoCompanion {
    static let previewDay = EventDay(id: "afterhours-preview", event: "Deccan After Hours", day: "Saturday, 14 November · 2026")
    static func schedule(for day: EventDay) -> [DemoScheduleItem] {
        guard DemoStaffAPI.days.contains(day) || day == previewDay else { return [] }
        if day == previewDay {
            return [DemoScheduleItem(id: "afterhours-welcome", time: "18:00–18:30", title: "Settle in", location: "The Courtyard · sample venue"),
                    DemoScheduleItem(id: "afterhours-ideas", time: "18:30–20:00", title: "Ideas & encounters", location: "The Courtyard · sample venue"),
                    DemoScheduleItem(id: "afterhours-evening", time: "20:00–21:00", title: "Stay a little longer", location: "The Courtyard · sample venue")]
        }
        let workshop = day.id == "workshop-1"
        return [DemoScheduleItem(id: day.id + "-welcome", time: "09:00–09:30", title: "Doors and welcome", location: "Welcome desk"),
                DemoScheduleItem(id: day.id + "-session", time: "09:30–12:00", title: workshop ? "Hands-on design studio" : "Community talks", location: workshop ? "Studio A" : "Main hall"),
                DemoScheduleItem(id: day.id + "-lunch", time: "12:00–13:00", title: "Lunch break", location: "Dining area")]
    }
    static func passes(for day: EventDay) -> [DemoPass] {
        guard DemoStaffAPI.days.contains(day) || day == previewDay else { return [] }
        return [DemoPass(id: day.id + "-sample", name: "Sample attendee pass", admission: .available, meal: .redeemed, party: .notIncluded)]
    }
}

@MainActor
final class AttendeeAgenda: ObservableObject {
    @Published private(set) var savedSessionIDs = Set<String>()
    func toggle(_ item: DemoScheduleItem, for day: EventDay) {
        guard DemoCompanion.schedule(for: day).contains(item) else { return }
        if savedSessionIDs.contains(item.id) { savedSessionIDs.remove(item.id) }
        else { savedSessionIDs.insert(item.id) }
    }
    func isSaved(_ item: DemoScheduleItem) -> Bool { savedSessionIDs.contains(item.id) }
}
struct EventCompanionView: View {
    let day: EventDay
    let wallet: Bool
    @State private var query = ""
    @State private var savedOnly = false
    @EnvironmentObject private var agenda: AttendeeAgenda
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if wallet { passContent }
            else { scheduleContent.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a session or room") }
        }
        .navigationTitle(wallet ? "Sample passes" : "Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .background(AttendeeStyle.canvas).tint(AttendeeStyle.accent)
    }
    private var sessions: [DemoScheduleItem] {
        DemoCompanion.schedule(for: day).filter {
            (!savedOnly || agenda.isSaved($0)) &&
                (query.isEmpty || "\($0.title) \($0.location)".localizedCaseInsensitiveContains(query))
        }
    }
    private var scheduleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PreviewBadge()
                AttendeeEventTitle(day: day)
                Label(day.day, systemImage: "calendar").font(.subheadline)
                VStack(alignment: .leading, spacing: 8) {
                    Text(day == DemoCompanion.previewDay ? "Make room for a good evening." : "A day for good ideas.").font(.system(.title2, design: .serif).weight(.medium))
                    Text("Sample agenda · illustrative local times.").font(.subheadline).foregroundStyle(AttendeeStyle.secondary)
                }
                Picker("Schedule view", selection: $savedOnly) {
                    Text("All sessions").tag(false)
                    Text("Saved").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("scheduleFilter")
                if sessions.isEmpty {
                    if !query.isEmpty { ContentUnavailableView.search(text: query) }
                    else if savedOnly {
                        ContentUnavailableView {
                            Label("Your evening, your way", systemImage: "bookmark")
                        } description: {
                            Text("Save a sample session to find it here. Your choices stay in this app session.")
                        } actions: {
                            Button("Explore all sessions") { savedOnly = false }
                                .buttonStyle(.bordered).controlSize(.large)
                        }.accessibilityIdentifier("savedScheduleEmpty")
                    } else {
                        ContentUnavailableView("No sample programme", systemImage: "calendar", description: Text("Sample content is available only for the preview events."))
                    }
                }
                ForEach(sessions) { item in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Circle().fill(AttendeeStyle.accent).frame(width: 6, height: 6).accessibilityHidden(true)
                                Text(item.time).font(.subheadline.monospacedDigit()).foregroundStyle(AttendeeStyle.secondary)
                            }
                            Text(item.title).font(.title3.weight(.semibold))
                            Label(item.location, systemImage: "mappin").font(.subheadline).foregroundStyle(AttendeeStyle.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        Button {
                            withAnimation(AttendeeMotion.reduced(reduceMotion) ? nil : AttendeeMotion.feedback) { agenda.toggle(item, for: day) }
                        } label: {
                            Image(systemName: agenda.isSaved(item) ? "bookmark.fill" : "bookmark")
                                .font(.title3).frame(width: 48, height: 48)
                                .background(AttendeeStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(AttendeePressStyle())
                            .accessibilityLabel(agenda.isSaved(item) ? "Remove \(item.title) from saved sessions" : "Save \(item.title)")
                            .accessibilityValue(agenda.isSaved(item) ? "Saved" : "Not saved")
                            .accessibilityIdentifier("save-" + item.id)
                    }.padding(24)
                        .background(AttendeeStyle.card, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AttendeeStyle.border.opacity(0.5), lineWidth: 1))
                }
                Text("Saved on this device for this app session · no account or live event changes.")
                    .font(.footnote).foregroundStyle(AttendeeStyle.secondary)
            }.padding(24).frame(maxWidth: 640).modifier(AttendeeReveal())
        }.foregroundStyle(AttendeeStyle.ink)
    }
    private var passContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PreviewBadge()
                if DemoCompanion.passes(for: day).isEmpty {
                    ContentUnavailableView("No sample pass", systemImage: "ticket", description: Text("Sample passes are available only for the preview events."))
                }
                ForEach(DemoCompanion.passes(for: day)) { pass in
                    VStack(alignment: .leading, spacing: 0) {
                        EventArtwork(showsHeadline: false).frame(height: 120).clipped().accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 20) {
                            AttendeeEventTitle(day: day)
                            Label(day.day, systemImage: "calendar").font(.subheadline)
                            Divider()
                            HStack(alignment: .top) {
                                Image(systemName: "person.crop.circle").font(.title)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(day == DemoCompanion.previewDay ? "Aarav Shah" : "Alex Morgan").font(.headline)
                                    Text("Synthetic attendee · sample pass").font(.caption).foregroundStyle(AttendeeStyle.secondary)
                                }
                            }
                            VStack(spacing: 12) {
                                Image(systemName: "ticket").font(.largeTitle).foregroundStyle(AttendeeStyle.accent)
                                Text("Entry code appears here").font(.headline)
                                Text("SAMPLE · no scannable credential").font(.caption)
                            }.frame(maxWidth: .infinity).padding(24)
                                .background(AttendeeStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
                            status("Admission", pass.admission)
                            Divider()
                            Text("Included with this sample").font(.subheadline.weight(.semibold))
                            status("Meal", pass.meal)
                            status("Party", pass.party)
                            Divider()
                            Label("Preview only · not valid for entry", systemImage: "lock").font(.subheadline.weight(.semibold))
                            Text("No admission QR is issued. Each status is independent; nothing can be redeemed from this preview.").font(.caption).foregroundStyle(AttendeeStyle.secondary)
                        }.padding(24)
                    }.background(AttendeeStyle.card).clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(AttendeeStyle.border.opacity(0.5), lineWidth: 1))
                }
                Text("Live passes and Apple Wallet export are not connected.").font(.footnote).foregroundStyle(AttendeeStyle.secondary)
            }.padding(24).frame(maxWidth: 640).modifier(AttendeeReveal())
        }.foregroundStyle(AttendeeStyle.ink)
    }
    private func status(_ name: String, _ value: DemoEntitlementStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.headline)
            Label(value.rawValue, systemImage: value == .available ? "ticket" : value == .redeemed ? "checkmark.circle" : "minus.circle")
                .font(.subheadline).foregroundStyle(AttendeeStyle.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct StaffActivity: Identifiable {
    let id = UUID()
    let dayID: String
    let attendeeID: String?
    let summary: String
    let time = Date()
}
struct StaffHistoryView: View {
    @ObservedObject var store: StaffStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section {
                Text(store.day?.event ?? "").font(.headline)
                Text(store.day?.day ?? "")
                Label("Demo · no live attendance changes", systemImage: "testtube.2")
                Text("This session only · latest 100 actions").font(.headline)
                Text("History is cleared on sign-out. Only verified check-in results confirm attendance. Scan entries do not.")
            }
            let entries = store.activity.filter { $0.dayID == store.day?.id }
            if entries.isEmpty { ContentUnavailableView("No activity for this day", systemImage: "clock", description: Text("Scans and submitted batches will appear here.")) }
            ForEach(entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    Label(entry.summary, systemImage: entry.summary == "Checked in" ? "checkmark.circle" : "info.circle")
                    Text(entry.time, style: .time).font(.caption)
                    if let attendeeID = entry.attendeeID {
                        Text("Attendee reference: \(attendeeID)").font(.caption)
                        Button("Look up attendee") {
                            dismiss()
                            Task { await store.search(attendeeID) }
                        }.frame(minHeight: 48).accessibilityHint("Returns to search without selecting or checking in the attendee")
                    }
                }.padding(.vertical, 4)
            }
        }.navigationTitle("Activity history")
    }
}
