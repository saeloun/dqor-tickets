import SwiftUI

/// Attendee-only presentation tokens; operational scanner states remain unchanged.
enum AttendeeStyle {
    static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let canvas = adaptive(UIColor(red: 0.973, green: 0.961, blue: 0.949, alpha: 1), UIColor(red: 0.10, green: 0.08, blue: 0.12, alpha: 1))
    static let cardUIColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.17, green: 0.14, blue: 0.19, alpha: 1) : .white }
    static let inkUIColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.97, green: 0.94, blue: 0.91, alpha: 1) : UIColor(red: 0.20, green: 0.149, blue: 0.192, alpha: 1) }
    static let card = Color(uiColor: cardUIColor)
    static let ink = Color(uiColor: inkUIColor)
    static let secondary = adaptive(UIColor(red: 0.39, green: 0.34, blue: 0.40, alpha: 1), UIColor(red: 0.78, green: 0.73, blue: 0.80, alpha: 1))
    static let border = adaptive(UIColor(red: 0.87, green: 0.82, blue: 0.84, alpha: 1), UIColor(red: 0.34, green: 0.28, blue: 0.36, alpha: 1))
    static let accent = adaptive(UIColor(red: 0.392, green: 0.184, blue: 0.278, alpha: 1), UIColor(red: 0.91, green: 0.68, blue: 0.80, alpha: 1))
}
enum AttendeeMotion {
    static func reduced(_ systemValue: Bool) -> Bool {
        #if DEBUG
        return systemValue || ProcessInfo.processInfo.arguments.contains("--reduce-motion-preview")
        #else
        return systemValue
        #endif
    }
    static let feedback = Animation.easeOut(duration: 0.22)
    static let reveal = Animation.easeOut(duration: 0.24)
}
struct AttendeePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !AttendeeMotion.reduced(reduceMotion) ? 0.985 : 1)
            .animation(AttendeeMotion.reduced(reduceMotion) ? nil : AttendeeMotion.feedback, value: configuration.isPressed)
    }
}
struct AttendeeReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    func body(content: Content) -> some View {
        content.opacity(visible || AttendeeMotion.reduced(reduceMotion) ? 1 : 0.94)
            .onAppear { withAnimation(AttendeeMotion.reduced(reduceMotion) ? nil : AttendeeMotion.reveal) { visible = true } }
    }
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
    @ScaledMetric(relativeTo: .title) private var headlineSize = 28.0
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: Self.cover ?? UIImage()).resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                if showsHeadline && !textSize.isAccessibilitySize {
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    Text("A little outside\nthe everyday.")
                        .font(.system(size: headlineSize, weight: .medium, design: .serif))
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
                    .clipShape(RoundedRectangle(cornerRadius: 24)).accessibilityHidden(true)
                HStack(alignment: .top) {
                    PreviewBadge()
                    Spacer(minLength: 8)
                    Text(isAfterHours ? "PUNE · 2026" : "SAMPLE EVENT").font(.caption.weight(.semibold)).tracking(1.2)
                        .foregroundStyle(AttendeeStyle.secondary).padding(.vertical, 8)
                }
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
                }.buttonStyle(AttendeePressStyle()).accessibilityIdentifier("eventSamplePass")
                NavigationLink { EventCompanionView(day: day, wallet: false) } label: {
                    HStack { Text("Explore the schedule").fixedSize(horizontal: false, vertical: true); Spacer(); Image(systemName: "arrow.right") }
                        .font(.headline).frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(AttendeePressStyle()).accessibilityIdentifier("eventSchedule")
                Divider()
                Text("Good ideas start\nwith a conversation.").font(.system(.title, design: .serif).weight(.medium))
                Text("A sample gathering for curious people, shared stories, and new connections. Explore the day, then take a look at how your pass will feel.")
                    .font(.body).foregroundStyle(AttendeeStyle.secondary)
                Text("This is a design preview. No booking, admission, or redemption is available.").font(.footnote).foregroundStyle(AttendeeStyle.secondary)
            }.padding(24).frame(maxWidth: 640).modifier(AttendeeReveal())
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
