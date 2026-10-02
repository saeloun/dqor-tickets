import SwiftUI

/// Attendee-only presentation tokens; operational scanner states remain unchanged.
enum AttendeeStyle {
    static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let canvas = adaptive(UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1), UIColor(red: 0.10, green: 0.08, blue: 0.12, alpha: 1))
    static let card = adaptive(.white, UIColor(red: 0.17, green: 0.14, blue: 0.19, alpha: 1))
    static let ink = adaptive(UIColor(red: 0.18, green: 0.12, blue: 0.20, alpha: 1), UIColor(red: 0.97, green: 0.94, blue: 0.91, alpha: 1))
    static let secondary = adaptive(UIColor(red: 0.39, green: 0.34, blue: 0.40, alpha: 1), UIColor(red: 0.78, green: 0.73, blue: 0.80, alpha: 1))
    static let accent = ink
}
struct PreviewBadge: View {
    var body: some View {
        Label("Synthetic preview", systemImage: "testtube.2")
            .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(AttendeeStyle.ink)
            .background(AttendeeStyle.card, in: Capsule())
    }
}

/// Original geometry drawn locally; no borrowed event imagery or network assets.
struct EventArtwork: View {
    var showsHeadline = true
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                Color(red: 0.25, green: 0.13, blue: 0.29)
                Circle().fill(Color(red: 0.94, green: 0.57, blue: 0.34))
                    .frame(width: w * 0.67).position(x: w * 0.73, y: h * 0.27)
                Circle().fill(Color(red: 0.68, green: 0.43, blue: 0.62))
                    .frame(width: w * 0.9).position(x: w * 0.03, y: h * 0.91)
                ForEach(0..<7) { index in
                    Ellipse().stroke(Color(red: 0.97, green: 0.85, blue: 0.69).opacity(0.85), lineWidth: 2)
                        .frame(width: w * (0.54 + Double(index) * 0.09), height: h * 0.85)
                        .rotationEffect(.degrees(-34)).position(x: w * 0.75, y: h * 0.81)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("DQOR").font(.system(size: 18, weight: .bold, design: .rounded)).tracking(4)
                    Spacer()
                    if showsHeadline { Text("Ideas meet.\nPeople connect.").font(.system(size: 34, weight: .medium, design: .serif)) }
                }.foregroundStyle(Color(red: 1, green: 0.96, blue: 0.88)).padding(28)
            }.clipped()
        }
    }
}

struct AttendeeEventView: View {
    let day: EventDay
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EventArtwork().aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
                PreviewBadge()
                VStack(alignment: .leading, spacing: 12) {
                    Text(day.event).font(.system(.largeTitle, design: .serif).weight(.semibold))
                    Text("Hosted by the DQOR community · demo").font(.subheadline).foregroundStyle(AttendeeStyle.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    metadata("calendar", title: day.day, subtitle: "Illustrative programme · local event time")
                    metadata("mappin.and.ellipse", title: "A place to come together", subtitle: "Sample venue · location to be confirmed")
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
            }.padding(24).frame(maxWidth: 640)
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
