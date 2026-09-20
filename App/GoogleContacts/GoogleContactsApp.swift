import SwiftUI

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
}
