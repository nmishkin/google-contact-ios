import Foundation
import GoogleContactsKit

struct FakeUITestAuth: AuthTokenProviding {
    func validAccessToken() async throws -> String { "fake-ui-test-token" }
}

final class SeededFakeAPIClient: PeopleAPIClientProtocol, @unchecked Sendable {
    private var storedPerson = PersonDTO(resourceName: "people/seed1", etag: "e1", names: [NameDTO(givenName: "Seed", familyName: "Person")])

    func listConnections(pageToken: String?, syncToken: String?) async throws -> ListConnectionsResponseDTO {
        ListConnectionsResponseDTO(connections: [ConnectionDTO(resourceName: storedPerson.resourceName, etag: storedPerson.etag, names: storedPerson.names)], nextPageToken: nil, nextSyncToken: "seed-token", totalItems: 1)
    }
    func listContactGroups() async throws -> [ContactGroupDTO] { [] }
    func createContact(_ person: PersonDTO) async throws -> PersonDTO { person }
    func updateContact(_ person: PersonDTO, updateFieldMask: String) async throws -> PersonDTO {
        storedPerson = person
        return person
    }
    func deleteContact(resourceName: String) async throws {}
    func modifyGroupMembers(groupResourceName: String, add: [String], remove: [String]) async throws {}
    func createContactGroup(name: String) async throws -> ContactGroupDTO { ContactGroupDTO(resourceName: "contactGroups/fake", etag: "e", name: name, formattedName: name, groupType: "USER_CONTACT_GROUP", memberCount: 0) }
    func updateContactGroup(resourceName: String, etag: String, name: String) async throws -> ContactGroupDTO { ContactGroupDTO(resourceName: resourceName, etag: etag, name: name, formattedName: name, groupType: "USER_CONTACT_GROUP", memberCount: 0) }
    func deleteContactGroup(resourceName: String) async throws {}
}
