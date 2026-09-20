import Testing
import Foundation
@testable import GoogleContactsKit

struct PeopleAPIModelsTests {
    func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    @Test func decodesFullPersonWithAllFieldGroups() throws {
        let data = try loadFixture("person_full")
        let person = try JSONDecoder().decode(PersonDTO.self, from: data)

        #expect(person.resourceName == "people/c123")
        #expect(person.names?.first?.givenName == "Ada")
        #expect(person.birthdays?.first?.date?.year == nil)
        #expect(person.birthdays?.first?.date?.month == 12)
        #expect(person.userDefined?.first?.key == "Mastodon")
        #expect(person.memberships?.contains { $0.contactGroupMembership.contactGroupResourceName == "contactGroups/starred" } == true)
        #expect(person.biographies?.first?.value == "Countess of Lovelace")
    }

    @Test func decodesListConnectionsPageWithSyncToken() throws {
        let data = try loadFixture("list_connections_page")
        let page = try JSONDecoder().decode(ListConnectionsResponseDTO.self, from: data)

        #expect(page.connections?.count == 2)
        #expect(page.nextSyncToken == "sync-token-abc123")
    }

    @Test func decodesContactGroupList() throws {
        let data = try loadFixture("contact_group_list")
        let list = try JSONDecoder().decode(ListContactGroupsResponseDTO.self, from: data)

        #expect(list.contactGroups.count == 3)
        #expect(list.contactGroups.first { $0.resourceName == "contactGroups/abcd1234" }?.groupType == "USER_CONTACT_GROUP")
    }

    @Test func expiredSyncTokenErrorIsRecognized() throws {
        let data = try loadFixture("error_expired_sync_token")
        let envelope = try JSONDecoder().decode(GoogleAPIErrorEnvelope.self, from: data)

        #expect(envelope.error.isExpiredSyncToken == true)
    }
}
