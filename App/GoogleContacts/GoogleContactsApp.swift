import SwiftUI

@main
struct GoogleContactsApp: App {
    @StateObject private var auth = GoogleSignInAuthProvider()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn {
                    Text("Signed in as \(auth.currentUserEmail ?? "?")") // replaced by RootSplitView in Task 10
                } else {
                    SignInView(auth: auth)
                }
            }
            .task { await auth.restorePreviousSignIn() }
        }
    }
}
