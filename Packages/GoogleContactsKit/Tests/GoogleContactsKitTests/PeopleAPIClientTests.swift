import Testing
import Foundation
@testable import GoogleContactsKit

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

struct FakeAuth: AuthTokenProviding {
    func validAccessToken() async throws -> String { "fake-token" }
}

@Suite(.serialized)
struct PeopleAPIClientTests {
    func makeClient() -> PeopleAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return PeopleAPIClient(auth: FakeAuth(), session: session)
    }

    @Test func listConnectionsSendsBearerTokenAndPersonFieldsAndDecodesSyncToken() async throws {
        var capturedRequest: URLRequest?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            let url = Bundle.module.url(forResource: "list_connections_page", withExtension: "json", subdirectory: "Fixtures")!
            let data = try Data(contentsOf: url)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let page = try await makeClient().listConnections(pageToken: nil, syncToken: nil)

        #expect(page.nextSyncToken == "sync-token-abc123")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer fake-token")
        #expect(capturedRequest?.url?.query?.contains("personFields=") == true)
    }

    @Test func listConnectionsWithSyncTokenSetsRequestSyncTokenTrue() async throws {
        var capturedURL: URL?
        StubURLProtocol.handler = { request in
            capturedURL = request.url
            let url = Bundle.module.url(forResource: "list_connections_page", withExtension: "json", subdirectory: "Fixtures")!
            let data = try Data(contentsOf: url)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        _ = try await makeClient().listConnections(pageToken: nil, syncToken: "prior-token")

        #expect(capturedURL?.query?.contains("syncToken=prior-token") == true)
        #expect(capturedURL?.query?.contains("requestSyncToken=true") == true)
    }

    @Test func expiredSyncTokenErrorThrowsExpiredSyncToken() async throws {
        StubURLProtocol.handler = { request in
            let url = Bundle.module.url(forResource: "error_expired_sync_token", withExtension: "json", subdirectory: "Fixtures")!
            let data = try Data(contentsOf: url)
            return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, data)
        }

        await #expect(throws: PeopleAPIError.expiredSyncToken) {
            _ = try await self.makeClient().listConnections(pageToken: nil, syncToken: "stale")
        }
    }

    @Test func updateContactSendsEtagInBodyAndPatchMethod() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            capturedBody = request.bodyDataForTesting()
            let responseJSON = #"{"resourceName":"people/c123","etag":"e2"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, responseJSON)
        }

        let person = PersonDTO(resourceName: "people/c123", etag: "e1", names: [NameDTO(givenName: "Ada")])
        let updated = try await makeClient().updateContact(person, updateFieldMask: "names")

        #expect(capturedRequest?.httpMethod == "PATCH")
        #expect(updated.etag == "e2")
        let bodyString = String(data: capturedBody ?? Data(), encoding: .utf8) ?? ""
        #expect(bodyString.contains("\"etag\":\"e1\""))
    }

    @Test func updateContactConflictThrowsEtagMismatchWithCurrentServerCopy() async throws {
        StubURLProtocol.handler = { request in
            let responseJSON = #"{"resourceName":"people/c123","etag":"server-etag","names":[{"givenName":"ServerName"}]}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!, responseJSON)
        }

        let person = PersonDTO(resourceName: "people/c123", etag: "stale-etag")
        do {
            _ = try await makeClient().updateContact(person, updateFieldMask: "names")
            Issue.record("expected etagMismatch to be thrown")
        } catch PeopleAPIError.etagMismatch(let current) {
            #expect(current.etag == "server-etag")
        }
    }

    @Test func deleteContact404IsTreatedAsSuccess() async throws {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        try await makeClient().deleteContact(resourceName: "people/gone")
        // no throw = success
    }

    @Test func rateLimitedResponseParsesRetryAfterHeader() async throws {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "30"])!, Data())
        }

        await #expect(throws: PeopleAPIError.rateLimited(retryAfter: 30)) {
            _ = try await self.makeClient().listContactGroups()
        }
    }

    @Test func createContactGroupPostsNameAndDecodesResult() async throws {
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedBody = request.bodyDataForTesting()
            let responseJSON = #"{"resourceName":"contactGroups/g1","etag":"g-e1","name":"Friends","groupType":"USER_CONTACT_GROUP"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, responseJSON)
        }

        let group = try await makeClient().createContactGroup(name: "Friends")

        #expect(group.resourceName == "contactGroups/g1")
        let bodyString = String(data: capturedBody ?? Data(), encoding: .utf8) ?? ""
        #expect(bodyString.contains("Friends"))
    }

    @Test func deleteContactGroupSucceedsOn200() async throws {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        try await makeClient().deleteContactGroup(resourceName: "contactGroups/g1")
    }
}

extension URLRequest {
    func bodyDataForTesting() -> Data? {
        httpBody ?? httpBodyStream.flatMap { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read > 0 { data.append(buffer, count: read) } else { break }
            }
            return data
        }
    }
}
