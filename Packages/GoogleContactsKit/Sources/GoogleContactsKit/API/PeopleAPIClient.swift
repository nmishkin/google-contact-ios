import Foundation

public protocol PeopleAPIClientProtocol: Sendable {
    func listConnections(pageToken: String?, syncToken: String?) async throws -> ListConnectionsResponseDTO
    func listContactGroups() async throws -> [ContactGroupDTO]
    func createContact(_ person: PersonDTO) async throws -> PersonDTO
    func updateContact(_ person: PersonDTO, updateFieldMask: String) async throws -> PersonDTO
    func deleteContact(resourceName: String) async throws
    func modifyGroupMembers(groupResourceName: String, add: [String], remove: [String]) async throws
    func createContactGroup(name: String) async throws -> ContactGroupDTO
    func updateContactGroup(resourceName: String, etag: String, name: String) async throws -> ContactGroupDTO
    func deleteContactGroup(resourceName: String) async throws
}

public final class PeopleAPIClient: PeopleAPIClientProtocol {
    private let auth: AuthTokenProviding
    private let session: URLSession
    private let baseURL = URL(string: "https://people.googleapis.com/v1/")!

    /// Every list/get call requests exactly these field groups, matching what `Contact` models.
    static let personFields = "names,nicknames,emailAddresses,phoneNumbers,addresses,organizations,urls,relations,userDefined,birthdays,biographies,memberships,photos"

    public init(auth: AuthTokenProviding, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    private func authorizedRequest(_ url: URL, method: String, body: Data? = nil) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PeopleAPIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PeopleAPIError.network("non-HTTP response")
        }
        return (data, http)
    }

    private func throwMappedError(status: Int, data: Data, headers: [AnyHashable: Any]) throws -> Never {
        if status == 429 {
            let retryAfter = (headers["Retry-After"] as? String).flatMap(TimeInterval.init)
            throw PeopleAPIError.rateLimited(retryAfter: retryAfter)
        }
        if let envelope = try? JSONDecoder().decode(GoogleAPIErrorEnvelope.self, from: data), envelope.error.isExpiredSyncToken {
            throw PeopleAPIError.expiredSyncToken
        }
        if status == 409, let current = try? JSONDecoder().decode(PersonDTO.self, from: data) {
            throw PeopleAPIError.etagMismatch(current: current)
        }
        let message = String(data: data, encoding: .utf8) ?? ""
        throw PeopleAPIError.http(status: status, message: message)
    }

    public func listConnections(pageToken: String?, syncToken: String?) async throws -> ListConnectionsResponseDTO {
        var components = URLComponents(url: baseURL.appendingPathComponent("people/me/connections"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "personFields", value: Self.personFields), URLQueryItem(name: "pageSize", value: "200")]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        if let syncToken {
            items.append(URLQueryItem(name: "syncToken", value: syncToken))
            items.append(URLQueryItem(name: "requestSyncToken", value: "true"))
        } else {
            items.append(URLQueryItem(name: "requestSyncToken", value: "true"))
        }
        components.queryItems = items

        let request = try await authorizedRequest(components.url!, method: "GET")
        let (data, http) = try await send(request)
        guard http.statusCode == 200 else { try throwMappedError(status: http.statusCode, data: data, headers: http.allHeaderFields) }
        do {
            return try JSONDecoder().decode(ListConnectionsResponseDTO.self, from: data)
        } catch {
            throw PeopleAPIError.decoding(String(describing: error))
        }
    }

    public func listContactGroups() async throws -> [ContactGroupDTO] {
        let url = baseURL.appendingPathComponent("contactGroups")
        let request = try await authorizedRequest(url, method: "GET")
        let (data, http) = try await send(request)
        guard http.statusCode == 200 else { try throwMappedError(status: http.statusCode, data: data, headers: http.allHeaderFields) }
        do {
            return try JSONDecoder().decode(ListContactGroupsResponseDTO.self, from: data).contactGroups
        } catch {
            throw PeopleAPIError.decoding(String(describing: error))
        }
    }

    public func createContact(_ person: PersonDTO) async throws -> PersonDTO {
        let url = baseURL.appendingPathComponent("people:createContact")
        let body = try JSONEncoder().encode(person)
        let request = try await authorizedRequest(url, method: "POST", body: body)
        let (data, http) = try await send(request)
        guard http.statusCode == 200 else { try throwMappedError(status: http.statusCode, data: data, headers: http.allHeaderFields) }
        return try JSONDecoder().decode(PersonDTO.self, from: data)
    }

    public func updateContact(_ person: PersonDTO, updateFieldMask: String) async throws -> PersonDTO {
        var components = URLComponents(url: baseURL.appendingPathComponent("\(person.resourceName):updateContact"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "updatePersonFields", value: updateFieldMask)]
        let body = try JSONEncoder().encode(person)
        let request = try await authorizedRequest(components.url!, method: "PATCH", body: body)
        let (data, http) = try await send(request)
        guard http.statusCode == 200 else { try throwMappedError(status: http.statusCode, data: data, headers: http.allHeaderFields) }
        return try JSONDecoder().decode(PersonDTO.self, from: data)
    }

    public func deleteContact(resourceName: String) async throws {
        let url = baseURL.appendingPathComponent("\(resourceName):deleteContact")
        let request = try await authorizedRequest(url, method: "DELETE")
        let (data, http) = try await send(request)
        guard http.statusCode == 200 || http.statusCode == 404 else {
            try throwMappedError(status: http.statusCode, data: data, headers: http.allHeaderFields)
        }
    }

    public func modifyGroupMembers(groupResourceName: String, add: [String], remove: [String]) async throws {
        let url = baseURL.appendingPathComponent("\(groupResourceName)/members:modify")
        let body = try JSONEncoder().encode(["resourceNamesToAdd": add, "resourceNamesToRemove": remove])
        let request = try await authorizedRequest(url, method: "POST", body: body)
        let (data, http) = try await send(request)
        guard http.statusCode == 200 else { try throwMappedError(status: http.statusCode, data: data, headers: http.allHeaderFields) }
    }

    public func createContactGroup(name: String) async throws -> ContactGroupDTO {
        let url = baseURL.appendingPathComponent("contactGroups")
        let body = try JSONEncoder().encode(["contactGroup": ["name": name]])
        let request = try await authorizedRequest(url, method: "POST", body: body)
        let (data, http) = try await send(request)
        guard http.statusCode == 200 else { try throwMappedError(status: http.statusCode, data: data, headers: http.allHeaderFields) }
        return try JSONDecoder().decode(ContactGroupDTO.self, from: data)
    }

    public func updateContactGroup(resourceName: String, etag: String, name: String) async throws -> ContactGroupDTO {
        struct UpdateContactGroupBody: Encodable {
            struct Group: Encodable { let name: String; let etag: String }
            let contactGroup: Group
            let updateGroupFields: String
        }
        let url = baseURL.appendingPathComponent(resourceName)
        let body = try JSONEncoder().encode(UpdateContactGroupBody(contactGroup: .init(name: name, etag: etag), updateGroupFields: "name"))
        let request = try await authorizedRequest(url, method: "PUT", body: body)
        let (data, http) = try await send(request)
        guard http.statusCode == 200 else { try throwMappedError(status: http.statusCode, data: data, headers: http.allHeaderFields) }
        return try JSONDecoder().decode(ContactGroupDTO.self, from: data)
    }

    public func deleteContactGroup(resourceName: String) async throws {
        let url = baseURL.appendingPathComponent(resourceName)
        let request = try await authorizedRequest(url, method: "DELETE")
        let (data, http) = try await send(request)
        guard http.statusCode == 200 || http.statusCode == 404 else {
            try throwMappedError(status: http.statusCode, data: data, headers: http.allHeaderFields)
        }
    }
}
