import SwiftUI

/// Attendee-only presentation tokens; operational scanner states remain unchanged.
enum AttendeeStyle {
    static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let canvas = adaptive(UIColor(red: 0.973, green: 0.961, blue: 0.949, alpha: 1), UIColor(red: 0.10, green: 0.08, blue: 0.12, alpha: 1))
    static let card = adaptive(.white, UIColor(red: 0.17, green: 0.14, blue: 0.19, alpha: 1))
    static let ink = adaptive(UIColor(red: 0.20, green: 0.149, blue: 0.192, alpha: 1), UIColor(red: 0.97, green: 0.94, blue: 0.91, alpha: 1))
    static let secondary = adaptive(UIColor(red: 0.39, green: 0.34, blue: 0.40, alpha: 1), UIColor(red: 0.78, green: 0.73, blue: 0.80, alpha: 1))
    static let accent = adaptive(UIColor(red: 0.392, green: 0.184, blue: 0.278, alpha: 1), UIColor(red: 0.91, green: 0.68, blue: 0.80, alpha: 1))
}
struct PreviewBadge: View {
    var body: some View {
        Label("Synthetic preview", systemImage: "testtube.2")
            .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(AttendeeStyle.ink)
            .background(AttendeeStyle.card, in: Capsule())
    }
}

/// Original DQOR artwork supplied by the theme owner; bundled, never fetched remotely.
struct EventArtwork: View {
    static let cover = UIImage(named: "deccan-cover.png", in: Bundle(for: ScannerController.self), compatibleWith: nil)
    var showsHeadline = true
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: Self.cover ?? UIImage()).resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                if showsHeadline {
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    Text("A little outside\nthe everyday.")
                        .font(.system(size: 28, weight: .medium, design: .serif))
                        .foregroundStyle(.white).padding(20)
                }
            }
        }
    }
}
struct AttendeeEventTitle: View {
    let day: EventDay
    var body: some View {
        if day.id == DemoCompanion.previewDay.id {
            VStack(alignment: .leading, spacing: 0) {
                Text("Deccan").font(.largeTitle.weight(.bold))
                Text("After Hours.").font(.system(.largeTitle, design: .serif).italic())
            }.accessibilityElement(children: .combine)
        } else { Text(day.event).font(.system(.largeTitle, design: .serif).weight(.semibold)) }
    }
}

struct AttendeeEventView: View {
    let day: EventDay
    private var isAfterHours: Bool { day.id == DemoCompanion.previewDay.id }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EventArtwork().aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
                PreviewBadge()
                VStack(alignment: .leading, spacing: 12) {
                    AttendeeEventTitle(day: day)
                    Text(isAfterHours ? "Hosted by Deccan Collective · fictional event" : "Hosted by the DQOR community · demo").font(.subheadline).foregroundStyle(AttendeeStyle.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    metadata("calendar", title: day.day, subtitle: isAfterHours ? "6:00–9:00 PM · India Standard Time" : "Illustrative programme · local event time")
                    metadata("mappin.and.ellipse", title: isAfterHours ? "The Courtyard, Pune" : "A place to come together", subtitle: "Illustrative venue · not a live booking")
                }
                NavigationLink { EventCompanionView(day: day, wallet: true) } label: {
                    Label("View sample pass", systemImage: "ticket")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(AttendeeStyle.canvas).background(AttendeeStyle.ink, in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityIdentifier("eventSamplePass")
                NavigationLink { EventCompanionView(day: day, wallet: false) } label: {
                    HStack { Text("Explore the schedule"); Spacer(); Image(systemName: "arrow.right") }
                        .font(.headline).frame(minHeight: 48)
                }.accessibilityIdentifier("eventSchedule")
                Divider()
                Text("Good ideas start\nwith a conversation.").font(.system(.title, design: .serif).weight(.medium))
                Text("A sample gathering for curious people, shared stories, and new connections. Explore the day, then take a look at how your pass will feel.")
                    .font(.body).foregroundStyle(AttendeeStyle.secondary)
                Text("This is a design preview. No booking, admission, or redemption is available.").font(.footnote).foregroundStyle(AttendeeStyle.secondary)
            }.padding(20).frame(maxWidth: 640)
        }.frame(maxWidth: .infinity).background(AttendeeStyle.canvas)
            .foregroundStyle(AttendeeStyle.ink).tint(AttendeeStyle.accent)
            .navigationTitle("Event preview").navigationBarTitleDisplayMode(.inline)
    }
    private func metadata(_ icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title3).frame(width: 48, height: 48)
                .background(AttendeeStyle.card, in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(AttendeeStyle.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}
