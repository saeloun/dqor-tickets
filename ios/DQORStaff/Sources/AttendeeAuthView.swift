import SwiftUI

struct AttendeeAccountView: View {
    @ObservedObject var store: AttendeeSessionStore
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    var previewBrowser: SyntheticAttendeeBrowser?
    var previewAPI: SyntheticAttendeeBridge?
    #endif
    var body: some View {
        ScrollViewReader { proxy in
            List {
                Group {
                    Text(store.phase == .ready ? "Your profile" : "You belong here.").font(.largeTitle.weight(.bold)).id("attendeeProfileTop")
                    if store.synthetic {
                        Label("Synthetic account rehearsal", systemImage: "testtube.2").font(.headline)
                        Text("Fictional private information only. No real sign-in, ticket credential or attendance change.").foregroundStyle(DQORStyle.secondary)
                    }
                    if store.revocationPending {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Previous session removal pending", systemImage: "lock.slash").font(.headline)
                            Text("Server revocation of a previous session has not been confirmed. That session is no longer used on this device.")
                            Button("Retry session removal") { store.retryRevocation() }.frame(minHeight: 48).accessibilityIdentifier("attendeeRevokeRetry")
                        }.padding(20).background(DQORStyle.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    switch store.phase {
                    case .unavailable:
                        Text("Continue in your browser to sign in and manage your profile.").accessibilityIdentifier("attendeeUnavailable")
                    case .signedOut:
                        Button(store.synthetic ? "Start synthetic sign-in" : "Sign in through system browser") { store.signIn() }.buttonStyle(.borderedProminent).foregroundStyle(DQORStyle.canvas).controlSize(.large).disabled(!store.canRequest).accessibilityIdentifier("attendeeSignIn")
                    case .authorizing, .exchanging, .loading:
                        ProgressView(store.phase == .authorizing ? "Waiting for sign-in return" : "Verifying private session").accessibilityIdentifier("attendeeLoading")
                        Button("Cancel sign-in", role: .cancel) { store.cancelLogin() }.frame(minHeight: 48).accessibilityIdentifier("attendeeCancel")
                    case .ready:
                        privateContent
                    }
                    websiteAccess
                    #if DEBUG
                    if store.synthetic, let browser = previewBrowser, let api = previewAPI { AttendeeAuthPreviewControls(store: store, browser: browser, api: api) }
                    #endif
                }.modifier(DQORListRows()).privacySensitive()
            }.modifier(DQORListAppearance()).tint(DQORStyle.accent)
                .safeAreaInset(edge: .top) {
                    if let message = store.message {
                        DQORRowCopy(text: message, size: .body, identifier: "attendeeMessage").fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(DQORStyle.canvas)
                    }
                }
                .navigationTitle("You").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if store.phase == .ready { Button("Sign out", role: .destructive) { store.logout() }.accessibilityIdentifier("attendeeLogoutToolbar") }
                        else if store.phase == .authorizing || store.phase == .exchanging || store.phase == .loading { Button("Cancel") { store.cancelLogin() }.accessibilityIdentifier("attendeeCancelToolbar") }
                    }
                }
                .overlay {
                    if scenePhase != .active && store.phase == .ready { DQORStyle.canvas.overlay { Label("Private information hidden", systemImage: "lock").font(.headline).padding() }.ignoresSafeArea() }
                }
                .onDisappear { store.cancelLogin() }
                .onChange(of: store.message) { _, message in
                    if UIAccessibility.isVoiceOverRunning, let message { UIAccessibility.post(notification: .announcement, argument: message) }
                }
                .onChange(of: store.phase) { _, phase in
                    if phase == .ready || phase == .signedOut { proxy.scrollTo("attendeeProfileTop", anchor: .top) }
                }
        }
    }
    private var privateContent: some View {
        Group {
            if let account = store.account {
                VStack(alignment: .leading, spacing: 12) {
                    Text(account.name ?? "Attendee").font(.title2.weight(.semibold)).accessibilityIdentifier("attendeeName")
                    Text(account.email).foregroundStyle(DQORStyle.secondary)
                    Text(store.stale ? "Saved in memory · not revalidated" : (store.synthetic ? "Synthetic server observation" : "Server observation")).font(.footnote).accessibilityIdentifier("attendeeFreshness")
                    if let checkedAt = store.accountCheckedAt { Text(checkedAt).font(.footnote).foregroundStyle(DQORStyle.secondary) }
                }.padding(20).background(DQORStyle.card, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 12) {
                Button("Refresh private information") { store.refresh() }.frame(minHeight: 48).disabled(store.loading).accessibilityIdentifier("attendeeRefresh")
                Button("Sign out", role: .destructive) { store.logout() }.frame(minHeight: 48).accessibilityIdentifier("attendeeLogout")
            }
            if store.loading { ProgressView("Updating private information") }

        }
    }
    private var websiteAccess: some View {
        Group {
            DQORWebsiteAction(destination: .account, identifier: "attendeeOfficialAccount", prominent: true)
            Text("Profile & privacy").font(.title2.weight(.semibold))
            DQORWebsiteAction(destination: .profile)
            DQORWebsiteAction(destination: .visibility)
            DQORWebsiteAction(destination: .preferences)
            DQORWebsiteAction(destination: .security)
            DQORWebsiteAction(destination: .tickets, identifier: "attendeeOfficialTickets")
            Text("Help & information").font(.title2.weight(.semibold)).padding(.top, 12)
            DQORWebsiteAction(destination: .help)
            DQORWebsiteAction(destination: .contact)
            DQORWebsiteAction(destination: .conduct)
        }
    }

}
struct AttendeePassList: View {
    @ObservedObject var store: AttendeeSessionStore
    var body: some View {
        Group {
            Text("Pass status").font(.title2.weight(.semibold))
            Text("Read-only information. These records contain no QR code and cannot be used to enter or check anyone in.").foregroundStyle(DQORStyle.secondary)
            if store.passes.isEmpty { ContentUnavailableView("No passes found", systemImage: "ticket", description: Text(store.synthetic ? "This synthetic account has no assigned pass records." : "Only passes assigned to your verified email appear here.")) }
            ForEach(store.passes) { pass in
                VStack(alignment: .leading, spacing: 12) {
                    Text(pass.type.name).font(.headline)
                    if let observed = store.passObservations[pass.id] { Text("Observed: \(observed)").font(.footnote).foregroundStyle(DQORStyle.secondary) }
                    HStack(spacing: 8) {
                        Image(systemName: pass.status == "confirmed" ? "checkmark.circle" : "info.circle").accessibilityHidden(true)
                        Text(pass.status.capitalized).accessibilityIdentifier("attendeePass-\(pass.id)")
                    }
                    Text("Admission: \(pass.admission.startsOn ?? "Not supplied") – \(pass.admission.endsOn ?? "Not supplied")").font(.footnote)
                    ForEach(pass.entry, id: \.date) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date)
                            Text(store.stale ? "Eligibility not revalidated" : (entry.eligible ? "Server reported eligible at observation" : "Server reported ineligible at observation")).font(.footnote)
                            if let recorded = entry.checkedInAt { Text("Recorded entry: \(recorded)").font(.footnote) }
                        }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(DQORStyle.card, in: RoundedRectangle(cornerRadius: 20))
            }
            if store.moreResults { Button("Load more pass records") { store.loadMore() }.frame(minHeight: 48).disabled(store.loading).accessibilityIdentifier("attendeeLoadMore") }
            if store.limitReached { Text("More pass records are available on the official website.").foregroundStyle(DQORStyle.secondary) }
        }
    }
}

#if DEBUG
private struct AttendeeAuthPreviewControls: View {
    @ObservedObject var store: AttendeeSessionStore
    @ObservedObject var browser: SyntheticAttendeeBrowser
    let api: SyntheticAttendeeBridge
    var body: some View {
        Group {
            Text("Synthetic test controls").font(.headline)
            if browser.waiting {
                Button("Simulate external browser return") { if let url = browser.callback() { store.receiveExternalCallback(url) } }.frame(minHeight: 48)
                Button("Approve synthetic return") { browser.finish() }.frame(minHeight: 48)
                Button("Return wrong state") { browser.finish(.wrongState) }.frame(minHeight: 48)
                Button("Return wrong origin") { browser.finish(.wrongOrigin) }.frame(minHeight: 48)
                Button("Return duplicate parameters") { browser.finish(.duplicate) }.frame(minHeight: 48)
            }
            ForEach(SyntheticAttendeeBridge.Scenario.allCases, id: \.rawValue) { scenario in
                Button(scenario.rawValue) { Task { await api.set(scenario); store.refresh() } }.frame(minHeight: 48).accessibilityIdentifier("attendeeScenario-\(scenario.rawValue)")
            }
        }
    }
}
#endif
