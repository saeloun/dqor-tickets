import SwiftUI

struct AttendeeAccountView: View {
    @ObservedObject var store: AttendeeSessionStore
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    var previewBrowser: SyntheticAttendeeBrowser?
    var previewAPI: SyntheticAttendeeBridge?
    #endif
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Label("Your account", systemImage: "person.crop.circle").font(.system(.largeTitle, design: .serif))
                if store.synthetic {
                    Label("Synthetic account rehearsal", systemImage: "testtube.2").font(.headline)
                    Text("Fictional private information only. No real sign-in, ticket credential or attendance change.").foregroundStyle(AttendeeStyle.secondary)
                }
                if let message = store.message { Text(message).accessibilityIdentifier("attendeeMessage") }
                if store.revocationPending {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Previous session removal pending", systemImage: "lock.slash").font(.headline)
                        Text("Server revocation of a previous session has not been confirmed. That session is no longer used on this device.")
                        Button("Retry session removal") { store.retryRevocation() }.frame(minHeight: 48).accessibilityIdentifier("attendeeRevokeRetry")
                    }.padding(20).background(AttendeeStyle.card, in: RoundedRectangle(cornerRadius: 20))
                }
                switch store.phase {
                case .unavailable:
                    Text(store.supportsHTTPSCallback ? AttendeeAuthError.unavailable.message : AttendeeAuthError.unsupportedPlatform.message).accessibilityIdentifier("attendeeUnavailable")
                case .signedOut:
                    Button(store.synthetic ? "Start synthetic sign-in" : "Sign in through system browser") { store.signIn() }.buttonStyle(.borderedProminent).foregroundStyle(AttendeeStyle.canvas).controlSize(.large).disabled(!store.canRequest).accessibilityIdentifier("attendeeSignIn")
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
            }.padding(24).frame(maxWidth: 640).privacySensitive()
        }.frame(maxWidth: .infinity).background(AttendeeStyle.canvas).foregroundStyle(AttendeeStyle.ink).tint(AttendeeStyle.accent)
            .navigationTitle("Your account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.phase == .ready { Button("Sign out", role: .destructive) { store.logout() }.accessibilityIdentifier("attendeeLogoutToolbar") }
                    else if store.phase == .authorizing || store.phase == .exchanging || store.phase == .loading { Button("Cancel") { store.cancelLogin() }.accessibilityIdentifier("attendeeCancelToolbar") }
                }
            }
            .overlay {
                if scenePhase != .active && store.phase == .ready { AttendeeStyle.canvas.overlay { Label("Private information hidden", systemImage: "lock").font(.headline).padding() }.ignoresSafeArea() }
            }
            .onAppear { store.foreground() }
            .onDisappear { store.cancelLogin() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { store.foreground() } }
    }
    private var privateContent: some View {
        Group {
            if let account = store.account {
                VStack(alignment: .leading, spacing: 12) {
                    Text(account.name ?? "Attendee").font(.title2.weight(.semibold)).accessibilityIdentifier("attendeeName")
                    Text(account.email).foregroundStyle(AttendeeStyle.secondary)
                    Text(store.stale ? "Saved in memory · not revalidated" : (store.synthetic ? "Synthetic server observation" : "Server observation")).font(.footnote).accessibilityIdentifier("attendeeFreshness")
                    if let checkedAt = store.accountCheckedAt { Text(checkedAt).font(.footnote).foregroundStyle(AttendeeStyle.secondary) }
                }.padding(20).background(AttendeeStyle.card, in: RoundedRectangle(cornerRadius: 20))
            }
            VStack(alignment: .leading, spacing: 12) {
                Button("Refresh private information") { store.refresh() }.frame(minHeight: 48).disabled(store.loading).accessibilityIdentifier("attendeeRefresh")
                Button("Sign out", role: .destructive) { store.logout() }.frame(minHeight: 48).accessibilityIdentifier("attendeeLogout")
            }
            if store.loading { ProgressView("Updating private information") }
            Text("Pass status").font(.title2.weight(.semibold))
            Text("Read-only information. These records contain no QR code and cannot be used to enter or check anyone in.").foregroundStyle(AttendeeStyle.secondary)
            if store.passes.isEmpty { ContentUnavailableView("No passes found", systemImage: "ticket", description: Text(store.synthetic ? "This synthetic account has no assigned pass records." : "Only passes assigned to your verified email appear here.")) }
            ForEach(store.passes) { pass in
                VStack(alignment: .leading, spacing: 12) {
                    Text(pass.type.name).font(.headline)
                    if let observed = store.passObservations[pass.id] { Text("Observed: \(observed)").font(.footnote).foregroundStyle(AttendeeStyle.secondary) }
                    Label(pass.status.capitalized, systemImage: pass.status == "confirmed" ? "checkmark.circle" : "info.circle")
                    Text("Admission: \(pass.admission.startsOn ?? "Not supplied") – \(pass.admission.endsOn ?? "Not supplied")").font(.footnote)
                    ForEach(pass.entry, id: \.date) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date)
                            Text(store.stale ? "Eligibility not revalidated" : (entry.eligible ? "Server reported eligible at observation" : "Server reported ineligible at observation")).font(.footnote)
                            if let recorded = entry.checkedInAt { Text("Recorded entry: \(recorded)").font(.footnote) }
                        }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(AttendeeStyle.card, in: RoundedRectangle(cornerRadius: 20)).accessibilityIdentifier("attendeePass-\(pass.id)")
            }
            if store.moreResults { Button("Load more pass records") { store.loadMore() }.frame(minHeight: 48).disabled(store.loading).accessibilityIdentifier("attendeeLoadMore") }
            if store.limitReached { Text("More pass records are available on the official website.").foregroundStyle(AttendeeStyle.secondary) }
        }
    }
    private var websiteAccess: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("On the official website", systemImage: "safari").font(.headline)
            Link("Open your account", destination: URL(string: "https://deccanqueenonrails.com/account")!).frame(minHeight: 48).accessibilityIdentifier("attendeeOfficialAccount")
            Link("Open your existing tickets", destination: URL(string: "https://deccanqueenonrails.com/tickets/mine")!).frame(minHeight: 48).accessibilityIdentifier("attendeeOfficialTickets")
        }.padding(20).background(AttendeeStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }
}
#if DEBUG
private struct AttendeeAuthPreviewControls: View {
    @ObservedObject var store: AttendeeSessionStore
    @ObservedObject var browser: SyntheticAttendeeBrowser
    let api: SyntheticAttendeeBridge
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
