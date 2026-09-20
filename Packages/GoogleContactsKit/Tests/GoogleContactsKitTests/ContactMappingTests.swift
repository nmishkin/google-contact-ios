import Testing
import Foundation
@testable import GoogleContactsKit

struct ContactMappingTests {
    @Test func applyPopulatesAllFieldsFromDTO() {
        let contact = Contact(resourceName: "people/c1", etag: "e0", updateTime: .now)
        let dto = PersonDTO(
            resourceName: "people/c1", etag: "e1",
            names: [NameDTO(metadata: FieldMetadataDTO(primary: true), givenName: "Ada", familyName: "Lovelace", middleName: "", phoneticGivenName: "", phoneticFamilyName: "")],
            emailAddresses: [LabeledStringDTO(metadata: FieldMetadataDTO(primary: true), value: "ada@example.com", type: "work")],
            organizations: [OrganizationDTO(metadata: FieldMetadataDTO(primary: true), name: "Analytical Engines", title: "Mathematician", department: nil, current: true)],
            userDefined: [UserDefinedFieldDTO(key: "Mastodon", value: "@ada@example.social")],
            birthdays: [BirthdayDTO(date: PartialDateDTO(year: nil, month: 12, day: 10))],
            biographies: [BiographyDTO(value: "Countess of Lovelace")],
            memberships: [MembershipDTO(contactGroupMembership: .init(contactGroupResourceName: "contactGroups/starred"))]
        )
        let starred = ContactGroup(resourceName: "contactGroups/starred", name: "starred", groupType: "SYSTEM_CONTACT_GROUP")

        contact.apply(dto, groupsByResourceName: ["contactGroups/starred": starred])

        #expect(contact.givenName == "Ada")
        #expect(contact.emails.first?.value == "ada@example.com")
        #expect(contact.organizations.first?.name == "Analytical Engines")
        #expect(contact.userDefinedFields.first?.label == "Mastodon")
        #expect(contact.birthday?.month == 12)
        #expect(contact.notes == "Countess of Lovelace")
        #expect(contact.isStarred == true)
        #expect(contact.etag == "e1")
    }

    @Test func asPersonDTORoundTripsLocalEdits() {
        let contact = Contact(resourceName: "people/c1", etag: "e1", updateTime: .now)
        contact.givenName = "Grace"
        contact.familyName = "Hopper"
        contact.emails = [LabeledValue(label: "work", value: "grace@example.com", isPrimary: true)]

        let dto = contact.asPersonDTO

        #expect(dto.names?.first?.givenName == "Grace")
        #expect(dto.emailAddresses?.first?.value == "grace@example.com")
        #expect(dto.etag == "e1")
    }

    @Test func fieldMaskOnlyListsChangedTopLevelGroups() {
        let original = PersonDTO(resourceName: "people/c1", etag: "e1", names: [NameDTO(givenName: "Ada")], emailAddresses: [LabeledStringDTO(value: "ada@example.com")])
        let updated = PersonDTO(resourceName: "people/c1", etag: "e1", names: [NameDTO(givenName: "Ada Marie")], emailAddresses: [LabeledStringDTO(value: "ada@example.com")])

        let mask = Contact.fieldMask(changedFrom: original, to: updated)

        #expect(mask == "names")
    }

    @Test func fieldMaskListsMultipleChangedGroupsCommaSeparated() {
        let original = PersonDTO(resourceName: "people/c1", etag: "e1", names: [NameDTO(givenName: "Ada")], phoneNumbers: [])
        let updated = PersonDTO(resourceName: "people/c1", etag: "e1", names: [NameDTO(givenName: "Ada")], phoneNumbers: [LabeledStringDTO(value: "+15550100")])

        let mask = Contact.fieldMask(changedFrom: original, to: updated)

        #expect(mask == "phoneNumbers")
    }
}
