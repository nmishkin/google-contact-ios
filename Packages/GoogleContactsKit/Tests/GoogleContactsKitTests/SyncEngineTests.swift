import Testing
import SwiftData
import Foundation
@testable import GoogleContactsKit

final class FakePeopleAPIClient: PeopleAPIClientProtocol, @unchecked Sendable {
    var connectionsPages: [[ConnectionDTO]] = [[]]
    var syncTokenToReturn = "token-1"
    var groups: [ContactGroupDTO] = []
    var throwExpiredOnNextCall = false
    var listConnectionsCallCount = 0
    var throwOnListContactGroups: (any Error)?

    func listConnections(pageToken: String?, syncToken: String?) async throws -> ListConnectionsResponseDTO {
        listConnectionsCallCount += 1
        if throwExpiredOnNextCall {
            throwExpiredOnNextCall = false
            throw PeopleAPIError.expiredSyncToken
        }
        let pageIndex = pageToken.flatMap(Int.init) ?? 0
        let page = connectionsPages[pageIndex]
        let isLast = pageIndex == connectionsPages.count - 1
        return ListConnectionsResponseDTO(connections: page, nextPageToken: isLast ? nil : String(pageIndex + 1), nextSyncToken: isLast ? syncTokenToReturn : nil, totalItems: nil)
    }

    func listContactGroups() async throws -> [ContactGroupDTO] {
        if let error = throwOnListContactGroups { throw error }
        return groups
    }
    func createContact(_ person: PersonDTO) async throws -> PersonDTO { person }
    func updateContact(_ person: PersonDTO, updateFieldMask: String) async throws -> PersonDTO { person }
    func deleteContact(resourceName: String) async throws {}
    func modifyGroupMembers(groupResourceName: String, add: [String], remove: [String]) async throws {}
    func createContactGroup(name: String) async throws -> ContactGroupDTO { ContactGroupDTO(resourceName: "contactGroups/fake", etag: "e", name: name, formattedName: name, groupType: "USER_CONTACT_GROUP", memberCount: 0) }
    func updateContactGroup(resourceName: String, etag: String, name: String) async throws -> ContactGroupDTO { ContactGroupDTO(resourceName: resourceName, etag: etag, name: name, formattedName: name, groupType: "USER_CONTACT_GROUP", memberCount: 0) }
    func deleteContactGroup(resourceName: String) async throws {}
}

final class InMemorySyncTokenStore: SyncTokenStoring, @unchecked Sendable {
    var token: String?
    func load() -> String? { token }
    func save(_ token: String?) { self.token = token }
}

@MainActor
struct SyncEngineTests {
    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Contact.self, LabeledValue.self, PostalAddress.self, Organization.self, ContactGroup.self, PendingMutation.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func fullSyncUpsertsAllPagesAndGroupsAndStoresSyncToken() async throws {
        let container = try makeContainer()
        let api = FakePeopleAPIClient()
        api.groups = [ContactGroupDTO(resourceName: "contactGroups/starred", etag: "g1", name: "starred", formattedName: "Starred", groupType: "SYSTEM_CONTACT_GROUP", memberCount: 1)]
        api.connectionsPages = [
            [ConnectionDTO(resourceName: "people/c1", etag: "e1", names: [NameDTO(givenName: "Ada")], memberships: [MembershipDTO(contactGroupMembership: .init(contactGroupResourceName: "contactGroups/starred"))])],
            [ConnectionDTO(resourceName: "people/c2", etag: "e2", names: [NameDTO(givenName: "Grace")])]
        ]
        let tokenStore = InMemorySyncTokenStore()
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: tokenStore)

        try await engine.fullSync()

        let context = ModelContext(container)
        let contacts = try context.fetch(FetchDescriptor<Contact>())
        #expect(contacts.count == 2)
        #expect(contacts.first { $0.resourceName == "people/c1" }?.isStarred == true)
        #expect(tokenStore.token == "token-1")
    }

    @Test func fullSyncDeletesLocalContactsNotPresentOnServer() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let stale = Contact(resourceName: "people/stale", etag: "old", updateTime: .now)
        context.insert(stale)
        try context.save()

        let api = FakePeopleAPIClient()
        api.connectionsPages = [[ConnectionDTO(resourceName: "people/c1", etag: "e1", names: [NameDTO(givenName: "Ada")])]]
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())

        try await engine.fullSync()

        let contacts = try context.fetch(FetchDescriptor<Contact>())
        #expect(contacts.count == 1)
        #expect(contacts.first?.resourceName == "people/c1")
    }

    @Test func incrementalSyncUpsertsAndDeletesUsingStoredSyncToken() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existing = Contact(resourceName: "people/c1", etag: "old", updateTime: .now)
        context.insert(existing)
        try context.save()

        let api = FakePeopleAPIClient()
        api.connectionsPages = [[
            ConnectionDTO(resourceName: "people/c1", etag: "new", names: [NameDTO(givenName: "Ada Updated")]),
            ConnectionDTO(resourceName: "people/gone", etag: nil, metadata: PersonMetadataDeletedDTO(deleted: true))
        ]]
        let tokenStore = InMemorySyncTokenStore()
        tokenStore.token = "prior-token"
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: tokenStore)

        try await engine.incrementalSync()

        let contacts = try context.fetch(FetchDescriptor<Contact>())
        #expect(contacts.count == 1)
        #expect(contacts.first?.givenName == "Ada Updated")
    }

    @Test func incrementalSyncFallsBackToFullSyncOnExpiredToken() async throws {
        let container = try makeContainer()
        let api = FakePeopleAPIClient()
        api.throwExpiredOnNextCall = true
        api.connectionsPages = [[ConnectionDTO(resourceName: "people/c1", etag: "e1", names: [NameDTO(givenName: "Ada")])]]
        let tokenStore = InMemorySyncTokenStore()
        tokenStore.token = "expired-token"
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: tokenStore)

        try await engine.incrementalSync()

        #expect(api.listConnectionsCallCount == 2) // first call throws expired, second is the full-sync retry
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<Contact>()).count == 1)
    }

    @Test func fullSyncStillSyncsContactsWhenListContactGroupsFails() async throws {
        let container = try makeContainer()
        let api = FakePeopleAPIClient()
        api.throwOnListContactGroups = PeopleAPIError.http(status: 403, message: "insufficient scope")
        api.connectionsPages = [[ConnectionDTO(resourceName: "people/c1", etag: "e1", names: [NameDTO(givenName: "Ada")])]]
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())

        try await engine.fullSync() // must not throw even though the groups call failed

        let context = ModelContext(container)
        let contacts = try context.fetch(FetchDescriptor<Contact>())
        #expect(contacts.count == 1)
        #expect(contacts.first?.givenName == "Ada")
    }
}
