import Foundation
import SwiftData

@MainActor
public final class ContactsRepository {
    private let modelContainer: ModelContainer
    private let syncEngine: SyncEngine
    private let apiClient: PeopleAPIClientProtocol

    // Uses the container's shared main context rather than a private one: callers (SwiftUI's
    // `@Query`/`\.modelContext`, bound to this same `mainContext` by the `.modelContainer(_:)`
    // view modifier) hand this repository live model objects, and SwiftData model mutations only
    // persist when saved through the context that object belongs to.
    private var context: ModelContext { modelContainer.mainContext }

    public struct ContactDraft {
        public var givenName: String = ""
        public var familyName: String = ""
        public var emails: [(label: String, value: String)] = []
        public var phones: [(label: String, value: String)] = []
        public var notes: String = ""

        public init(givenName: String = "", familyName: String = "", emails: [(label: String, value: String)] = [], phones: [(label: String, value: String)] = [], notes: String = "") {
            self.givenName = givenName
            self.familyName = familyName
            self.emails = emails
            self.phones = phones
            self.notes = notes
        }
    }

    public init(modelContainer: ModelContainer, syncEngine: SyncEngine, apiClient: PeopleAPIClientProtocol) {
        self.modelContainer = modelContainer
        self.syncEngine = syncEngine
        self.apiClient = apiClient
    }

    public func createContact(_ draft: ContactDraft) throws -> Contact {
        let contact = Contact(resourceName: "local/\(UUID().uuidString)", etag: "", updateTime: .now)
        contact.givenName = draft.givenName
        contact.familyName = draft.familyName
        contact.notes = draft.notes
        contact.emails = draft.emails.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
        contact.phones = draft.phones.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
        contact.isPendingCreate = true
        context.insert(contact)

        let mutation = PendingMutation(kind: .create, targetResourceName: contact.resourceName, payload: try JSONEncoder().encode(contact.asPersonDTO))
        context.insert(mutation)
        try context.save()
        Task { try? await syncEngine.drainOutbox() }
        return contact
    }

    public func save(edit contact: Contact, previousSnapshot: PersonDTO) throws {
        let updated = contact.asPersonDTO
        let mask = Contact.fieldMask(changedFrom: previousSnapshot, to: updated)
        guard !mask.isEmpty else {
            try context.save()
            return
        }
        let mutation = PendingMutation(kind: .update(fieldMask: mask), targetResourceName: contact.resourceName, payload: try JSONEncoder().encode(updated))
        context.insert(mutation)
        try context.save()
        Task { try? await syncEngine.drainOutbox() }
    }

    public func delete(_ contact: Contact) throws {
        contact.isDeletedLocally = true
        let mutation = PendingMutation(kind: .delete, targetResourceName: contact.resourceName, payload: Data())
        context.insert(mutation)
        try context.save()
        Task { try? await syncEngine.drainOutbox() }
    }

    public func setLabel(_ group: ContactGroup, on contact: Contact, isMember: Bool) throws {
        if isMember {
            if !contact.memberships.contains(where: { $0.resourceName == group.resourceName }) {
                contact.memberships.append(group)
            }
        } else {
            contact.memberships.removeAll { $0.resourceName == group.resourceName }
        }
        let payload = try JSONEncoder().encode(GroupMembershipChangePayload(groupResourceName: group.resourceName, add: isMember))
        let mutation = PendingMutation(kind: .groupMembershipChange, targetResourceName: contact.resourceName, payload: payload)
        context.insert(mutation)
        try context.save()
        Task { try? await syncEngine.drainOutbox() }
    }

    public func refresh() async throws {
        try await syncEngine.incrementalSync()
        try await syncEngine.drainOutbox()
    }

    // MARK: Labels
    // Labels change rarely, so unlike contact edits these call the API directly (blocking on the
    // network) rather than going through the outbox/etag machinery built for contacts.

    public func createLabel(name: String) async throws -> ContactGroup {
        let dto = try await apiClient.createContactGroup(name: name)
        let group = ContactGroup(resourceName: dto.resourceName, name: dto.name, groupType: dto.groupType, etag: dto.etag ?? "")
        context.insert(group)
        try context.save()
        return group
    }

    public func renameLabel(_ group: ContactGroup, to newName: String) async throws {
        let dto = try await apiClient.updateContactGroup(resourceName: group.resourceName, etag: group.etag, name: newName)
        group.name = dto.name
        group.etag = dto.etag ?? ""
        try context.save()
    }

    public func deleteLabel(_ group: ContactGroup) async throws {
        try await apiClient.deleteContactGroup(resourceName: group.resourceName)
        context.delete(group)
        try context.save()
    }
}
