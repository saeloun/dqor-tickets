import AuthenticationServices
import UIKit

@MainActor
final class SystemAttendeeBrowser: NSObject, AttendeeBrowserAuthorizing, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var completion: CheckedContinuation<URL, Error>?
    private var anchor: ASPresentationAnchor?
    private var generation = 0
    func authorize(_ url: URL) async throws -> URL {
        guard AttendeeActivation.liveEnabled else { throw AttendeeAuthError.unavailable }
        guard #available(iOS 17.4, *) else { throw AttendeeAuthError.unsupportedPlatform }
        guard session == nil, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "deccanqueenonrails.com", parts.percentEncodedHost == "deccanqueenonrails.com", parts.port == nil,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.percentEncodedPath == "/account/native/authorize",
              let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { throw AttendeeAuthError.unavailable }
        anchor = window; generation += 1
        let current = generation
        return try await withCheckedThrowingContinuation { completion in
            self.completion = completion
            let session = ASWebAuthenticationSession(url: url, callback: .https(host: "deccanqueenonrails.com", path: "/native/attendee/ios/callback")) { [weak self] callback, error in
                Task { @MainActor in
                    guard let self, current == self.generation else { return }
                    if let callback { self.finish(.success(callback)) }
                    else { self.finish(.failure(error == nil ? AttendeeAuthError.invalidCallback : AttendeeAuthError.canceled)) }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() { finish(.failure(AttendeeAuthError.unavailable)) }
        }
    }
    func receiveExternal(_ url: URL) -> Bool {
        guard completion != nil else { return false }
        let previous = session
        finish(.success(url)); generation += 1; previous?.cancel()
        return true
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor ?? ASPresentationAnchor() }
    func cancel() { generation += 1; session?.cancel(); finish(.failure(AttendeeAuthError.canceled)) }
    private func finish(_ result: Result<URL, Error>) {
        let previous = completion; completion = nil; session = nil; anchor = nil
        previous?.resume(with: result)
    }
}
