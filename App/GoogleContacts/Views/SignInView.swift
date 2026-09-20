import SwiftUI
import GoogleSignInSwift

struct SignInView: View {
    @ObservedObject var auth: GoogleSignInAuthProvider
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Sign in with Google to access your contacts")
                .font(.headline)
                .multilineTextAlignment(.center)
            GoogleSignInButton {
                Task { await signIn() }
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: 400)
    }

    private func signIn() async {
        do {
            #if os(iOS)
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.keyWindow?.rootViewController else { return }
            try await auth.signIn(presenting: root)
            #elseif os(macOS)
            guard let window = NSApplication.shared.windows.first else { return }
            try await auth.signIn(presenting: window)
            #endif
            errorMessage = nil
        } catch {
            errorMessage = "Sign-in was cancelled or failed. Please try again."
        }
    }
}
