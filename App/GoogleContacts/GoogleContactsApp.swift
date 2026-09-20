import SwiftUI

@main
struct GoogleContactsApp: App {
    @StateObject private var auth = GoogleSignInAuthProvider()
    @State private var environment: AppEnvironment?

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
                await auth.restorePreviousSignIn()
                if environment == nil { environment = AppEnvironment(auth: auth) }
            }
            .onChange(of: auth.isSignedIn) { _, signedIn in
                if signedIn, environment == nil { environment = AppEnvironment(auth: auth) }
            }
        }
    }
}
