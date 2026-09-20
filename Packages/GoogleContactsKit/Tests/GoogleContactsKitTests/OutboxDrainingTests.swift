import Testing
import SwiftData
import Foundation
@testable import GoogleContactsKit

final class RecordingPeopleAPIClient: PeopleAPIClientProtocol, @unchecked Sendable {
    var createdPersons: [PersonDTO] = []
    var updatedPersons: [(PersonDTO, String)] = []
    var deletedResourceNames: [String] = []
    var nextCreateResourceName = "people/server-assigned-1"
    var updateShouldThrowConflictWithServerName: String?

    func listConnections(pageToken: String?, syncToken: String?) async throws -> ListConnectionsResponseDTO { .init(connections: [], nextPageToken: nil, nextSyncToken: "t", totalItems: 0) }
    func listContactGroups() async throws -> [ContactGroupDTO] { [] }

    func createContact(_ person: PersonDTO) async throws -> PersonDTO {
        createdPersons.append(person)
        return PersonDTO(resourceName: nextCreateResourceName, etag: "server-e1", names: person.names)
    }

    func updateContact(_ person: PersonDTO, updateFieldMask: String) async throws -> PersonDTO {
        if let conflictName = updateShouldThrowConflictWithServerName {
            throw PeopleAPIError.etagMismatch(current: PersonDTO(resourceName: person.resourceName, etag: conflictName, names: [NameDTO(givenName: "ServerWon")]))
        }
        updatedPersons.append((person, updateFieldMask))
        return PersonDTO(resourceName: person.resourceName, etag: "server-e2", names: person.names)
    }

    func deleteContact(resourceName: String) async throws { deletedResourceNames.append(resourceName) }
    func modifyGroupMembers(groupResourceName: String, add: [String], remove: [String]) async throws {}
    func createContactGroup(name: String) async throws -> ContactGroupDTO { ContactGroupDTO(resourceName: "contactGroups/fake", etag: "e", name: name, formattedName: name, groupType: "USER_CONTACT_GROUP", memberCount: 0) }
    func updateContactGroup(resourceName: String, etag: String, name: String) async throws -> ContactGroupDTO { ContactGroupDTO(resourceName: resourceName, etag: etag, name: name, formattedName: name, groupType: "USER_CONTACT_GROUP", memberCount: 0) }
    func deleteContactGroup(resourceName: String) async throws {}
}

@MainActor
struct OutboxDrainingTests {
    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Contact.self, LabeledValue.self, PostalAddress.self, Organization.self, ContactGroup.self, PendingMutation.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func drainingCreateMutationAssignsServerResourceNameAndEtag() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let contact = Contact(resourceName: "local/uuid-1", etag: "", updateTime: .now)
        contact.givenName = "Ada"
        contact.isPendingCreate = true
        context.insert(contact)
        let mutation = PendingMutation(kind: .create, targetResourceName: "local/uuid-1", payload: try JSONEncoder().encode(contact.asPersonDTO))
        context.insert(mutation)
        try context.save()

        let api = RecordingPeopleAPIClient()
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())

        try await engine.drainOutbox()

        #expect(api.createdPersons.count == 1)
        let contacts = try context.fetch(FetchDescriptor<Contact>())
        #expect(contacts.first?.resourceName == "people/server-assigned-1")
        #expect(contacts.first?.isPendingCreate == false)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
    }

    @Test func drainingUpdateMutationClearsOnSuccess() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let contact = Contact(resourceName: "people/c1", etag: "e1", updateTime: .now)
        contact.givenName = "Ada"
        context.insert(contact)
        let mutation = PendingMutation(kind: .update(fieldMask: "names"), targetResourceName: "people/c1", payload: try JSONEncoder().encode(contact.asPersonDTO))
        context.insert(mutation)
        try context.save()

        let api = RecordingPeopleAPIClient()
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())

        try await engine.drainOutbox()

        #expect(api.updatedPersons.count == 1)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Contact>()).first?.etag == "server-e2")
    }

    @Test func etagMismatchLeavesMutationQueuedAndRecordsConflict() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let contact = Contact(resourceName: "people/c1", etag: "stale", updateTime: .now)
        context.insert(contact)
        let mutation = PendingMutation(kind: .update(fieldMask: "names"), targetResourceName: "people/c1", payload: try JSONEncoder().encode(contact.asPersonDTO))
        context.insert(mutation)
        try context.save()

        let api = RecordingPeopleAPIClient()
        api.updateShouldThrowConflictWithServerName = "server-etag"
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())

        try await engine.drainOutbox()

        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).count == 1)
        let conflicts = await engine.pendingConflicts()
        #expect(conflicts.first?.resourceName == "people/c1")
        #expect(conflicts.first?.serverCopy.etag == "server-etag")
    }

    @Test func resolveConflictKeepLocalRepushesWithFreshEtag() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let contact = Contact(resourceName: "people/c1", etag: "stale", updateTime: .now)
        contact.givenName = "MyEdit"
        context.insert(contact)
        let mutation = PendingMutation(kind: .update(fieldMask: "names"), targetResourceName: "people/c1", payload: try JSONEncoder().encode(contact.asPersonDTO))
        context.insert(mutation)
        try context.save()

        let api = RecordingPeopleAPIClient()
        api.updateShouldThrowConflictWithServerName = "server-etag"
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())
        try await engine.drainOutbox() // produces the conflict

        api.updateShouldThrowConflictWithServerName = nil
        try await engine.resolveConflict(resourceName: "people/c1", keepLocal: true)

        #expect(await engine.pendingConflicts().isEmpty)
        #expect(api.updatedPersons.last?.0.names?.first?.givenName == "MyEdit")
    }

    @Test func resolveConflictUseTheirsDiscardsMutationAndAdoptsServerCopy() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let contact = Contact(resourceName: "people/c1", etag: "stale", updateTime: .now)
        contact.givenName = "MyEdit"
        context.insert(contact)
        let mutation = PendingMutation(kind: .update(fieldMask: "names"), targetResourceName: "people/c1", payload: try JSONEncoder().encode(contact.asPersonDTO))
        context.insert(mutation)
        try context.save()

        let api = RecordingPeopleAPIClient()
        api.updateShouldThrowConflictWithServerName = "server-etag"
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())
        try await engine.drainOutbox()

        try await engine.resolveConflict(resourceName: "people/c1", keepLocal: false)

        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Contact>()).first?.givenName == "ServerWon")
    }

    @Test func deleteMutationOn404IsTreatedAsSuccess() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let contact = Contact(resourceName: "people/gone", etag: "e1", updateTime: .now)
        contact.isDeletedLocally = true
        context.insert(contact)
        let mutation = PendingMutation(kind: .delete, targetResourceName: "people/gone", payload: Data())
        context.insert(mutation)
        try context.save()

        let api = RecordingPeopleAPIClient()
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())

        try await engine.drainOutbox()

        #expect(api.deletedResourceNames == ["people/gone"])
        #expect(try context.fetch(FetchDescriptor<Contact>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
    }
}
