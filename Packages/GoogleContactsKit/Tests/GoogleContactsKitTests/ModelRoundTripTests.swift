import Testing
import Foundation
import SwiftData
@testable import GoogleContactsKit

@MainActor
struct ModelRoundTripTests {
    func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Contact.self, LabeledValue.self, PostalAddress.self, Organization.self, ContactGroup.self, PendingMutation.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func contactRoundTripsAllFieldsIncludingPartialBirthday() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let contact = Contact(resourceName: "people/c1", etag: "e1", updateTime: .now)
        contact.givenName = "Ada"
        contact.familyName = "Lovelace"
        contact.birthday = DateComponents(month: 12, day: 10) // year-less birthday
        contact.notes = "Met at a conference"
        contact.emails.append(LabeledValue(label: "work", value: "ada@example.com", isPrimary: true))
        contact.userDefinedFields.append(LabeledValue(label: "Mastodon", value: "@ada@example.social", isPrimary: false))
        context.insert(contact)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Contact>()).first
        #expect(fetched?.givenName == "Ada")
        #expect(fetched?.birthday?.year == nil)
        #expect(fetched?.birthday?.month == 12)
        #expect(fetched?.emails.first?.value == "ada@example.com")
        #expect(fetched?.userDefinedFields.first?.label == "Mastodon")
    }

    @Test func contactGroupMembershipRoundTrips() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let contact = Contact(resourceName: "people/c2", etag: "e2", updateTime: .now)
        let group = ContactGroup(resourceName: "contactGroups/g1", name: "Friends", groupType: "USER_CONTACT_GROUP")
        contact.memberships = [group]
        context.insert(contact)
        context.insert(group)
        try context.save()

        let fetchedGroup = try context.fetch(FetchDescriptor<ContactGroup>()).first
        #expect(fetchedGroup?.members.count == 1)
        #expect(fetchedGroup?.members.first?.resourceName == "people/c2")
    }

    @Test func pendingMutationPayloadRoundTrips() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let mutation = PendingMutation(kind: .update(fieldMask: "names,emailAddresses"), targetResourceName: "people/c1", payload: Data("{}".utf8))
        context.insert(mutation)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PendingMutation>()).first
        #expect(fetched?.kind == .update(fieldMask: "names,emailAddresses"))
    }
}
