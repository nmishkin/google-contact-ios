import Foundation
import GoogleSignIn
import GoogleContactsKit

@MainActor
final class GoogleSignInAuthProvider: ObservableObject, AuthTokenProviding {
    @Published var currentUserEmail: String?
    @Published var isSignedIn = false

    private let scopes = ["https://www.googleapis.com/auth/contacts"]

    func restorePreviousSignIn() async {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            currentUserEmail = user.profile?.email
            isSignedIn = true
        } catch {
            isSignedIn = false
        }
    }

    #if os(iOS)
    func signIn(presenting viewController: UIViewController) async throws {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController, hint: nil, additionalScopes: scopes)
        currentUserEmail = result.user.profile?.email
        isSignedIn = true
    }
    #elseif os(macOS)
    func signIn(presenting window: NSWindow) async throws {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window, hint: nil, additionalScopes: scopes)
        currentUserEmail = result.user.profile?.email
        isSignedIn = true
    }
    #endif

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUserEmail = nil
        isSignedIn = false
    }

    // MARK: AuthTokenProviding
    nonisolated func validAccessToken() async throws -> String {
        let user = try await MainActor.run { GIDSignIn.sharedInstance.currentUser }
        guard let user else { throw AuthError.notSignedIn }
        try await user.refreshTokensIfNeeded()
        return await MainActor.run { user.accessToken.tokenString }
    }
}

enum AuthError: Error { case notSignedIn }
