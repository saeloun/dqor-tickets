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
    static func schedule(for day: EventDay) -> [DemoScheduleItem] {
        guard DemoStaffAPI.days.contains(day) else { return [] }
        let workshop = day.id == "workshop-1"
        return [DemoScheduleItem(id: day.id + "-welcome", time: "09:00–09:30", title: "Doors and welcome", location: "Welcome desk"),
                DemoScheduleItem(id: day.id + "-session", time: "09:30–12:00", title: workshop ? "Hands-on design studio" : "Community talks", location: workshop ? "Studio A" : "Main hall"),
                DemoScheduleItem(id: day.id + "-lunch", time: "12:00–13:00", title: "Lunch break", location: "Dining area")]
    }
    static func passes(for day: EventDay) -> [DemoPass] {
        guard DemoStaffAPI.days.contains(day) else { return [] }
        return [DemoPass(id: day.id + "-sample", name: "Sample attendee pass", admission: .available, meal: .redeemed, party: .notIncluded)]
    }
}

struct EventCompanionView: View {
    let day: EventDay
    let wallet: Bool
    @State private var query = ""
    var body: some View {
        Group {
            if wallet { content }
            else { content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a session or room") }
        }.navigationTitle(wallet ? "Sample passes" : "Schedule")
    }
    private var content: some View {
        List {
            Section {
                Text(day.event).font(.headline)
                Text(day.day)
                Label("Synthetic preview", systemImage: "testtube.2")
                Text(wallet ? "These sample passes are not your tickets and cannot be used for entry or redemption." : "Sample agenda · times are illustrative local event times, not a published schedule.")
                    .font(.subheadline)
            }
            if wallet {
                ForEach(DemoCompanion.passes(for: day)) { pass in
                    Section(header: Text(pass.name).font(.headline).foregroundStyle(.primary)) {
                        status("Admission", pass.admission)
                        status("Meal", pass.meal)
                        status("Party", pass.party)
                        Text("Admission and each redemption are tracked separately. This preview cannot change any status.").font(.caption)
                    }
                }
                Section { Text("Live passes and Apple Wallet export are not connected.") }
            } else {
                let sessions = DemoCompanion.schedule(for: day).filter { query.isEmpty || "\($0.title) \($0.location)".localizedCaseInsensitiveContains(query) }
                if sessions.isEmpty { ContentUnavailableView.search(text: query) }
                ForEach(sessions) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.time).font(.subheadline.monospacedDigit())
                        Text(item.title).font(.headline)
                        Label(item.location, systemImage: "mappin")
                    }.padding(.vertical, 6).accessibilityElement(children: .combine)
                }
            }
        }
    }
    private func status(_ name: String, _ value: DemoEntitlementStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline)
            Label(value.rawValue, systemImage: value == .available ? "ticket" : value == .redeemed ? "checkmark.circle" : "minus.circle")
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
