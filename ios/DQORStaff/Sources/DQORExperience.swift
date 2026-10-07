import SwiftUI

enum DQORStyle {
    static let canvas = Color(uiColor: .systemBackground)
    static let card = Color(uiColor: .systemBackground)
    static let muted = Color(uiColor: .secondarySystemBackground)
    static let inkUIColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.96, alpha: 1) : UIColor(white: 0.15, alpha: 1) }
    static let ink = Color(uiColor: inkUIColor)
    static let secondaryUIColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.72, alpha: 1) : UIColor(white: 0.36, alpha: 1) }
    static let secondary = Color(uiColor: secondaryUIColor)
    static let border = Color(uiColor: .separator)
    static let accent = AttendeeStyle.adaptive(UIColor(red: 0.61, green: 0.12, blue: 0.26, alpha: 1), UIColor(red: 0.98, green: 0.55, blue: 0.65, alpha: 1))
}

struct DQORListRows: ViewModifier {
    func body(content: Content) -> some View {
        content.listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
            .listRowSeparator(.hidden).listRowBackground(DQORStyle.canvas)
    }
}

struct DQORListAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.plain).scrollContentBackground(.hidden).buttonStyle(.borderless)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .background(DQORStyle.canvas).foregroundStyle(DQORStyle.ink)
    }
}

struct DQORPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16).padding(.vertical, 4)
            .foregroundStyle(Color.white)
            .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DQORStyle.secondary, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(AttendeeMotion.reduced(reduceMotion) ? nil : AttendeeMotion.feedback, value: configuration.isPressed)
    }
}

struct DQORHero: View {
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("THE DQOR EXPERIENCE").font(.caption.weight(.semibold)).tracking(1)
            Text("Ideas worth\nshowing up for.").font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center) {
                Text("Explore the programme").font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Image(systemName: "arrow.right").accessibilityHidden(true)
            }.padding(.top, 8)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background {
                Canvas { context, size in
                    let center = CGPoint(x: size.width * 0.89, y: size.height * 0.51)
                    for step in 0..<9 {
                        let radius = size.height * (0.32 + Double(step) * 0.09)
                        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.16)), lineWidth: 1)
                    }
                    if !textSize.isAccessibilitySize {
                        let diameter = min(size.width * 0.23, 92)
                        let rect = CGRect(x: size.width - diameter - 18, y: size.height * 0.39, width: diameter, height: diameter)
                        context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.58, green: 0.16, blue: 0.30)))
                    }
                }.background(Color(white: 0.10)).accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

enum DQORCopySize { case row, largeTitle, title, title3, body, footnote }

struct DQORRowCopy: UIViewRepresentable {
    let text: String
    var emphasized = false
    var size: DQORCopySize = .row
    var reversed = false
    var identifier: String? = nil
    @ScaledMetric(relativeTo: .largeTitle) private var largeTitleSize = 34.0
    @ScaledMetric(relativeTo: .title2) private var titleSize = 22.0
    @ScaledMetric(relativeTo: .title3) private var title3Size = 20.0
    @ScaledMetric(relativeTo: .body) private var bodySize = 17.0
    @ScaledMetric(relativeTo: .footnote) private var footnoteSize = 13.0
    @ScaledMetric(relativeTo: .headline) private var headlineSize = 17.0
    @ScaledMetric(relativeTo: .subheadline) private var detailSize = 15.0
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.adjustsFontForContentSizeCategory = true
        label.isAccessibilityElement = true
        label.accessibilityTraits = .staticText
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.accessibilityLabel = text
        label.accessibilityIdentifier = identifier
        let pointSize: Double
        switch size {
        case .row: pointSize = emphasized ? headlineSize : detailSize
        case .largeTitle: pointSize = largeTitleSize
        case .title: pointSize = titleSize
        case .title3: pointSize = title3Size
        case .body: pointSize = bodySize
        case .footnote: pointSize = footnoteSize
        }
        label.font = .systemFont(ofSize: pointSize, weight: emphasized ? (size == .largeTitle ? .bold : .semibold) : .regular)
        label.textColor = reversed ? .systemBackground : (emphasized ? DQORStyle.inkUIColor : DQORStyle.secondaryUIColor)
        label.backgroundColor = reversed ? DQORStyle.inkUIColor : .systemBackground
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

struct DQORActionRow: View {
    let title: String
    let detail: String
    let symbol: String
    var external = false
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol).font(.title3).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                DQORRowCopy(text: title, emphasized: true)
                DQORRowCopy(text: detail)
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: external ? "arrow.up.right" : "chevron.right").font(.subheadline)
                .foregroundStyle(DQORStyle.secondary).accessibilityHidden(true)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .foregroundStyle(DQORStyle.ink).background(DQORStyle.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DQORStyle.border, lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .ignore).accessibilityLabel(title + ". " + detail)
    }
}

enum DQORWebsiteDestination: String, CaseIterable {
    case account, profile, visibility, preferences, security, tickets, help, contact, conduct
    var path: String {
        switch self {
        case .account: return "/account"
        case .profile, .visibility, .preferences, .security: return "/account/settings"
        case .tickets: return "/tickets/mine"
        case .help: return "/faq"
        case .contact: return "/contact"
        case .conduct: return "/coc"
        }
    }
    var url: URL { URL(string: "https://deccanqueenonrails.com" + path)! }
    var title: String {
        switch self {
        case .account: return "Your website account"
        case .profile: return "Edit your profile"
        case .visibility: return "Privacy & visibility"
        case .preferences: return "Email & browser preferences"
        case .security: return "Account security"
        case .tickets: return "Open your existing tickets"
        case .help: return "Help with DQOR"
        case .contact: return "Contact the team"
        case .conduct: return "Code of conduct"
        }
    }
    var detail: String {
        switch self {
        case .account: return "Tickets, connections and referral details."
        case .profile: return "Name, bio, photo, website and social links."
        case .visibility: return "Manage directory and public-attendee visibility."
        case .preferences: return "Choose announcement email and browser preferences."
        case .security: return "Manage your password and website sign-in."
        case .tickets: return "Retrieve your actual entry pass on the website."
        case .help: return "Answers and practical event information."
        case .contact: return "Find the official event contact details."
        case .conduct: return "Our shared expectations for a welcoming event."
        }
    }
    var symbol: String {
        switch self {
        case .account: return "person.crop.circle"
        case .profile: return "pencil"
        case .visibility: return "eye"
        case .preferences: return "envelope"
        case .security: return "lock"
        case .tickets: return "ticket"
        case .help: return "questionmark.circle"
        case .contact: return "bubble.left"
        case .conduct: return "heart"
        }
    }
}

struct DQORWebsiteAction: View {
    let destination: DQORWebsiteDestination
    var identifier: String?
    var prominent = false
    @Environment(\.openURL) private var openURL
    @State private var failure = false
    @State private var opening = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if prominent { action.buttonStyle(DQORPrimaryButtonStyle()) }
            else { action.buttonStyle(AttendeePressStyle()) }
            if failure { Text("The website could not be opened. Try again.").font(.subheadline).foregroundStyle(DQORStyle.ink).accessibilityIdentifier("websiteOpenFailure-" + destination.rawValue) }
        }
    }
    private var action: some View {
        Button {
            guard !opening else { return }
            opening = true; failure = false
            openURL(destination.url) { accepted in
                opening = false
                failure = !accepted
                if !accepted { UIAccessibility.post(notification: .announcement, argument: "The website could not be opened. Try again.") }
            }
        } label: {
            if prominent {
                Label(destination == .tickets ? "Open entry pass on website" : "Continue on website", systemImage: "arrow.up.right")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                DQORActionRow(title: destination.title, detail: destination.detail, symbol: destination.symbol, external: true)
            }
        }.disabled(opening)
            .accessibilityHint("Opens the official website in your browser")
            .accessibilityIdentifier(identifier ?? "website-" + destination.rawValue)
    }

}

struct DQORPassView: View {
    @ObservedObject var store: AttendeeSessionStore
    let openAccount: () -> Void
    var body: some View {
        List {
            Group {
                DQORRowCopy(text: "Your pass", emphasized: true, size: .largeTitle)
                DQORRowCopy(text: "Keep it close. You're part of it.", size: .body)
                if store.synthetic { Label("Synthetic account rehearsal", systemImage: "testtube.2").font(.headline) }
                if store.phase == .ready {
                    if let message = store.message { Text(message).accessibilityIdentifier("passMessage") }
                    AttendeePassList(store: store)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack { DQORRowCopy(text: "DQOR", emphasized: true, size: .title, reversed: true); Spacer(); Image(systemName: "ticket").font(.title2).accessibilityHidden(true) }
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(DQORStyle.canvas).background(DQORStyle.ink)
                        VStack(alignment: .leading, spacing: 12) {
                            DQORRowCopy(text: "Your entry pass stays on the official website.", emphasized: true, size: .title3)
                            DQORRowCopy(text: "Open it securely in your browser. Use the email associated with your booking.", size: .body)
                            DQORRowCopy(text: "No ticket is stored on this device.", size: .footnote)
                        }.padding(.horizontal, 24).padding(.bottom, 24)
                    }.background(DQORStyle.card).clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DQORStyle.border, lineWidth: 0.5))
                }
                DQORWebsiteAction(destination: .tickets, identifier: "attendeeOfficialTickets", prominent: true)
                Button(action: openAccount) {
                    DQORActionRow(title: "Your account", detail: "Profile, privacy and preferences.", symbol: "person.crop.circle")
                }.buttonStyle(AttendeePressStyle()).accessibilityIdentifier("passOpenAccount")
                DQORWebsiteAction(destination: .help)
                DQORRowCopy(text: "Ticket access opens in your browser. Your website sign-in is separate from this app.", size: .footnote)
            }.modifier(DQORListRows()).privacySensitive()
        }.modifier(DQORListAppearance())
            .navigationTitle("Pass").navigationBarTitleDisplayMode(.inline)
    }
}
