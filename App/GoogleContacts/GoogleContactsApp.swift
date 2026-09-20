import SwiftUI

private struct SignOutActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var signOut: () -> Void {
        get { self[SignOutActionKey.self] }
        set { self[SignOutActionKey.self] = newValue }
    }
}

@main
struct GoogleContactsApp: App {
    @StateObject private var auth = GoogleSignInAuthProvider()
    @State private var environment: AppEnvironment?

    private var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("UI_TESTING") }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn, let environment {
                    RootSplitView()
                        .environmentObject(environment)
                        .modelContainer(environment.modelContainer)
                        .environment(\.signOut, signOut)
                } else if auth.isSignedIn {
                    ProgressView()
                } else {
                    SignInView(auth: auth)
                }
            }
            .task {
                if isUITesting {
                    environment = AppEnvironment(auth: FakeUITestAuth(), apiClientOverride: SeededFakeAPIClient())
                    auth.isSignedIn = true
                    try? await environment?.syncEngine.fullSync()
                } else {
                    await auth.restorePreviousSignIn()
                    if environment == nil { environment = AppEnvironment(auth: auth) }
                }
            }
            .onChange(of: auth.isSignedIn) { _, signedIn in
                if signedIn, environment == nil { environment = AppEnvironment(auth: auth) }
            }
        }
    }

    private func signOut() {
        auth.signOut()
        try? environment?.wipeLocalData()
        environment = nil
    }
}
