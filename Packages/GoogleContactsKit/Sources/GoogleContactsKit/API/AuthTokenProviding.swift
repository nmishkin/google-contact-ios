import Foundation

/// Abstraction over whatever supplies a bearer token. The concrete GoogleSignIn-backed
/// implementation lives in the app target, which is free to import the GoogleSignIn SDK;
/// GoogleContactsKit only ever depends on this protocol.
public protocol AuthTokenProviding: Sendable {
    func validAccessToken() async throws -> String
}
