import Testing
import SwiftData
import Foundation
@testable import GoogleContactsKit

@MainActor
struct ContactsRepositoryTests {
    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Contact.self, LabeledValue.self, PostalAddress.self, Organization.self, ContactGroup.self, PendingMutation.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func createContactInsertsLocallyAsPendingWithCreateMutation() throws {
        let container = try makeContainer()
        let api = RecordingPeopleAPIClient()
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())
        let repo = ContactsRepository(modelContainer: container, syncEngine: engine, apiClient: api)

        let draft = ContactsRepository.ContactDraft(givenName: "New", familyName: "Person")
        let contact = try repo.createContact(draft)

        #expect(contact.isPendingCreate == true)
        #expect(contact.resourceName.hasPrefix("local/"))
        let context = container.mainContext
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        #expect(mutations.count == 1)
        #expect(mutations.first?.kind == .create)
    }

    @Test func saveEditWritesLocallyImmediatelyAndQueuesMinimalFieldMask() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let contact = Contact(resourceName: "people/c1", etag: "e1", updateTime: .now)
        contact.givenName = "Ada"
        context.insert(contact)
        try context.save()
        let snapshot = contact.asPersonDTO

        let api = RecordingPeopleAPIClient()
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())
        let repo = ContactsRepository(modelContainer: container, syncEngine: engine, apiClient: api)

        contact.givenName = "Ada Marie"
        try repo.save(edit: contact, previousSnapshot: snapshot)

        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        #expect(mutations.count == 1)
        if case .update(let mask) = mutations.first?.kind {
            #expect(mask == "names")
        } else {
            Issue.record("expected .update mutation")
        }
    }

    @Test func saveEditWithNoChangesQueuesNoMutation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let contact = Contact(resourceName: "people/c1", etag: "e1", updateTime: .now)
        contact.givenName = "Ada"
        context.insert(contact)
        try context.save()
        let snapshot = contact.asPersonDTO

        let api = RecordingPeopleAPIClient()
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())
        let repo = ContactsRepository(modelContainer: container, syncEngine: engine, apiClient: api)

        try repo.save(edit: contact, previousSnapshot: snapshot) // no field actually changed

        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
    }

    @Test func deleteMarksLocallyDeletedAndQueuesDeleteMutation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let contact = Contact(resourceName: "people/c1", etag: "e1", updateTime: .now)
        context.insert(contact)
        try context.save()

        let api = RecordingPeopleAPIClient()
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())
        let repo = ContactsRepository(modelContainer: container, syncEngine: engine, apiClient: api)

        try repo.delete(contact)

        #expect(contact.isDeletedLocally == true)
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        #expect(mutations.first?.kind == .delete)
    }

    @Test func setLabelQueuesGroupMembershipChangeMutation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let contact = Contact(resourceName: "people/c1", etag: "e1", updateTime: .now)
        let group = ContactGroup(resourceName: "contactGroups/g1", name: "Friends", groupType: "USER_CONTACT_GROUP")
        context.insert(contact)
        context.insert(group)
        try context.save()

        let api = RecordingPeopleAPIClient()
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())
        let repo = ContactsRepository(modelContainer: container, syncEngine: engine, apiClient: api)

        try repo.setLabel(group, on: contact, isMember: true)

        #expect(contact.memberships.contains { $0.resourceName == "contactGroups/g1" })
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        #expect(mutations.first?.kind == .groupMembershipChange)
    }

    @Test func createLabelCallsAPIAndInsertsLocalGroupFromServerResponse() async throws {
        let container = try makeContainer()
        let api = RecordingPeopleAPIClient()
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())
        let repo = ContactsRepository(modelContainer: container, syncEngine: engine, apiClient: api)

        let group = try await repo.createLabel(name: "Friends")

        #expect(group.resourceName == "contactGroups/fake")
        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<ContactGroup>()).count == 1)
    }

    @Test func deleteLabelCallsAPIAndRemovesLocalGroup() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let group = ContactGroup(resourceName: "contactGroups/g1", name: "Friends", groupType: "USER_CONTACT_GROUP", etag: "g-e1")
        context.insert(group)
        try context.save()

        let api = RecordingPeopleAPIClient()
        let engine = SyncEngine(modelContainer: container, apiClient: api, syncTokenStore: InMemorySyncTokenStore())
        let repo = ContactsRepository(modelContainer: container, syncEngine: engine, apiClient: api)

        try await repo.deleteLabel(group)

        #expect(try context.fetch(FetchDescriptor<ContactGroup>()).isEmpty)
    }
}
