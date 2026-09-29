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

    public struct AddressDraft {
        public var label: String
        public var street: String
        public var city: String
        public var region: String
        public var postalCode: String
        public var country: String

        public init(label: String = "home", street: String = "", city: String = "", region: String = "", postalCode: String = "", country: String = "") {
            self.label = label
            self.street = street
            self.city = city
            self.region = region
            self.postalCode = postalCode
            self.country = country
        }
    }

    public struct OrganizationDraft {
        public var name: String
        public var title: String
        public var department: String
        public var isCurrent: Bool

        public init(name: String = "", title: String = "", department: String = "", isCurrent: Bool = false) {
            self.name = name
            self.title = title
            self.department = department
            self.isCurrent = isCurrent
        }
    }

    public struct ContactDraft {
        public var givenName: String = ""
        public var familyName: String = ""
        public var middleName: String = ""
        public var phoneticGivenName: String = ""
        public var phoneticFamilyName: String = ""
        public var nickname: String = ""
        public var emails: [(label: String, value: String)] = []
        public var phones: [(label: String, value: String)] = []
        public var addresses: [AddressDraft] = []
        public var organizations: [OrganizationDraft] = []
        public var urls: [(label: String, value: String)] = []
        public var relations: [(label: String, value: String)] = []
        public var userDefinedFields: [(label: String, value: String)] = []
        public var birthday: DateComponents?
        public var notes: String = ""

        public init(givenName: String = "", familyName: String = "", middleName: String = "", phoneticGivenName: String = "", phoneticFamilyName: String = "", nickname: String = "", emails: [(label: String, value: String)] = [], phones: [(label: String, value: String)] = [], addresses: [AddressDraft] = [], organizations: [OrganizationDraft] = [], urls: [(label: String, value: String)] = [], relations: [(label: String, value: String)] = [], userDefinedFields: [(label: String, value: String)] = [], birthday: DateComponents? = nil, notes: String = "") {
            self.givenName = givenName
            self.familyName = familyName
            self.middleName = middleName
            self.phoneticGivenName = phoneticGivenName
            self.phoneticFamilyName = phoneticFamilyName
            self.nickname = nickname
            self.emails = emails
            self.phones = phones
            self.addresses = addresses
            self.organizations = organizations
            self.urls = urls
            self.relations = relations
            self.userDefinedFields = userDefinedFields
            self.birthday = birthday
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
        contact.middleName = draft.middleName
        contact.phoneticGivenName = draft.phoneticGivenName
        contact.phoneticFamilyName = draft.phoneticFamilyName
        contact.nickname = draft.nickname
        contact.notes = draft.notes
        contact.birthday = draft.birthday
        contact.emails = draft.emails.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
        contact.phones = draft.phones.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
        contact.urls = draft.urls.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
        contact.relations = draft.relations.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
        contact.userDefinedFields = draft.userDefinedFields.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
        contact.addresses = draft.addresses.map { PostalAddress(label: $0.label, street: $0.street, city: $0.city, region: $0.region, postalCode: $0.postalCode, country: $0.country) }
        contact.organizations = draft.organizations.map { Organization(name: $0.name, title: $0.title, department: $0.department, isCurrent: $0.isCurrent) }
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
