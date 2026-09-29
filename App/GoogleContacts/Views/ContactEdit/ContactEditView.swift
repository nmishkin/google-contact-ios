import SwiftUI
import SwiftData
import GoogleContactsKit

struct ContactEditView: View {
    /// Pass an existing contact to edit it, or `nil` to create a new one.
    let existingContact: Contact?
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ContactGroup> { $0.groupType == "USER_CONTACT_GROUP" }, sort: \ContactGroup.name)
    private var allLabels: [ContactGroup]

    // Default fields
    @State private var givenName = ""
    @State private var familyName = ""
    @State private var organizations: [(name: String, title: String, department: String, isCurrent: Bool)] = []
    @State private var emails: [(label: String, value: String)] = []
    @State private var phones: [(label: String, value: String)] = []
    @State private var notes = ""

    // Fields behind "Show more"
    @State private var showMoreFields = false
    @State private var nickname = ""
    @State private var middleName = ""
    @State private var phoneticGivenName = ""
    @State private var phoneticFamilyName = ""
    @State private var hasBirthday = false
    @State private var birthdayDate = Date()
    @State private var birthdayHasYear = true
    @State private var addresses: [(label: String, street: String, city: String, region: String, postalCode: String, country: String)] = []
    @State private var urls: [(label: String, value: String)] = []
    @State private var relations: [(label: String, value: String)] = []
    @State private var userDefinedFields: [(label: String, value: String)] = []

    @State private var previousSnapshot: PersonDTO?

    init(contact: Contact) {
        self.existingContact = contact
    }
    init() {
        self.existingContact = nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("First name", text: $givenName)
                    TextField("Last name", text: $familyName)
                }
                Section("Organization") {
                    ForEach(organizations.indices, id: \.self) { i in
                        OrganizationRow(name: $organizations[i].name, title: $organizations[i].title, department: $organizations[i].department, isCurrent: $organizations[i].isCurrent) {
                            organizations.remove(at: i)
                        }
                    }
                    Button("Add organization") { organizations.append((name: "", title: "", department: "", isCurrent: false)) }
                }
                Section("Email") {
                    ForEach(emails.indices, id: \.self) { i in
                        LabeledValueRow(label: $emails[i].label, value: $emails[i].value, commonLabels: ["home", "work", "other"]) {
                            emails.remove(at: i)
                        }
                    }
                    Button("Add email") { emails.append((label: "home", value: "")) }
                }
                Section("Phone") {
                    ForEach(phones.indices, id: \.self) { i in
                        LabeledValueRow(label: $phones[i].label, value: $phones[i].value, commonLabels: ["mobile", "home", "work"]) {
                            phones.remove(at: i)
                        }
                    }
                    Button("Add phone") { phones.append((label: "mobile", value: "")) }
                }
                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 80)
                }

                if !showMoreFields {
                    Button("Show more fields") { showMoreFields = true }
                } else {
                    Section("Nickname & Alternate Names") {
                        TextField("Nickname", text: $nickname)
                        TextField("Middle name", text: $middleName)
                        TextField("Phonetic first name", text: $phoneticGivenName)
                        TextField("Phonetic last name", text: $phoneticFamilyName)
                    }
                    Section("Birthday") {
                        Toggle("Has birthday", isOn: $hasBirthday)
                        if hasBirthday {
                            Toggle("Include year", isOn: $birthdayHasYear)
                            DatePicker("Birthday", selection: $birthdayDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        }
                    }
                    Section("Addresses") {
                        ForEach(addresses.indices, id: \.self) { i in
                            AddressRow(label: $addresses[i].label, street: $addresses[i].street, city: $addresses[i].city, region: $addresses[i].region, postalCode: $addresses[i].postalCode, country: $addresses[i].country) {
                                addresses.remove(at: i)
                            }
                        }
                        Button("Add address") { addresses.append((label: "home", street: "", city: "", region: "", postalCode: "", country: "")) }
                    }
                    Section("Links") {
                        ForEach(urls.indices, id: \.self) { i in
                            LabeledValueRow(label: $urls[i].label, value: $urls[i].value, commonLabels: ["homepage", "work", "other"]) {
                                urls.remove(at: i)
                            }
                        }
                        Button("Add link") { urls.append((label: "homepage", value: "")) }
                    }
                    Section("Relations") {
                        ForEach(relations.indices, id: \.self) { i in
                            LabeledValueRow(label: $relations[i].label, value: $relations[i].value, commonLabels: ["spouse", "child", "parent", "friend"]) {
                                relations.remove(at: i)
                            }
                        }
                        Button("Add relation") { relations.append((label: "spouse", value: "")) }
                    }
                    Section("Custom Fields") {
                        ForEach(userDefinedFields.indices, id: \.self) { i in
                            LabeledValueRow(label: $userDefinedFields[i].label, value: $userDefinedFields[i].value, commonLabels: []) {
                                userDefinedFields.remove(at: i)
                            }
                        }
                        Button("Add custom field") { userDefinedFields.append((label: "", value: "")) }
                    }
                }

                if existingContact != nil {
                    Section("Labels") {
                        ForEach(allLabels) { group in
                            let isMember = existingContact?.memberships.contains { $0.resourceName == group.resourceName } ?? false
                            Toggle(group.name, isOn: Binding(
                                get: { isMember },
                                set: { newValue in
                                    guard let contact = existingContact else { return }
                                    try? environment.repository.setLabel(group, on: contact, isMember: newValue)
                                }
                            ))
                        }
                    }
                }
            }
            .navigationTitle(existingContact == nil ? "New Contact" : "Edit Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: populateFromExistingContact)
        }
    }

    private var birthdayComponents: DateComponents? {
        guard hasBirthday else { return nil }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: birthdayDate)
        return DateComponents(year: birthdayHasYear ? parts.year : nil, month: parts.month, day: parts.day)
    }

    private func populateFromExistingContact() {
        guard let contact = existingContact else { return }
        givenName = contact.givenName
        familyName = contact.familyName
        middleName = contact.middleName
        phoneticGivenName = contact.phoneticGivenName
        phoneticFamilyName = contact.phoneticFamilyName
        nickname = contact.nickname
        notes = contact.notes
        emails = contact.emails.map { (label: $0.label, value: $0.value) }
        phones = contact.phones.map { (label: $0.label, value: $0.value) }
        organizations = contact.organizations.map { (name: $0.name, title: $0.title, department: $0.department, isCurrent: $0.isCurrent) }
        addresses = contact.addresses.map { (label: $0.label, street: $0.street, city: $0.city, region: $0.region, postalCode: $0.postalCode, country: $0.country) }
        urls = contact.urls.map { (label: $0.label, value: $0.value) }
        relations = contact.relations.map { (label: $0.label, value: $0.value) }
        userDefinedFields = contact.userDefinedFields.map { (label: $0.label, value: $0.value) }
        if let birthday = contact.birthday {
            hasBirthday = true
            birthdayHasYear = birthday.year != nil
            var components = birthday
            if components.year == nil { components.year = Calendar.current.component(.year, from: Date()) }
            birthdayDate = Calendar.current.date(from: components) ?? Date()
        }
        previousSnapshot = contact.asPersonDTO
        if !middleName.isEmpty || !phoneticGivenName.isEmpty || !phoneticFamilyName.isEmpty || !addresses.isEmpty || !urls.isEmpty || !relations.isEmpty || !userDefinedFields.isEmpty || hasBirthday {
            showMoreFields = true
        }
    }

    private func save() {
        do {
            if let contact = existingContact, let previousSnapshot {
                contact.givenName = givenName
                contact.familyName = familyName
                contact.middleName = middleName
                contact.phoneticGivenName = phoneticGivenName
                contact.phoneticFamilyName = phoneticFamilyName
                contact.nickname = nickname
                contact.notes = notes
                contact.birthday = birthdayComponents
                contact.emails = emails.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
                contact.phones = phones.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
                contact.urls = urls.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
                contact.relations = relations.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
                contact.userDefinedFields = userDefinedFields.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
                contact.addresses = addresses.map { PostalAddress(label: $0.label, street: $0.street, city: $0.city, region: $0.region, postalCode: $0.postalCode, country: $0.country) }
                contact.organizations = organizations.map { Organization(name: $0.name, title: $0.title, department: $0.department, isCurrent: $0.isCurrent) }
                try environment.repository.save(edit: contact, previousSnapshot: previousSnapshot)
            } else {
                let draft = ContactsRepository.ContactDraft(
                    givenName: givenName,
                    familyName: familyName,
                    middleName: middleName,
                    phoneticGivenName: phoneticGivenName,
                    phoneticFamilyName: phoneticFamilyName,
                    nickname: nickname,
                    emails: emails,
                    phones: phones,
                    addresses: addresses.map { ContactsRepository.AddressDraft(label: $0.label, street: $0.street, city: $0.city, region: $0.region, postalCode: $0.postalCode, country: $0.country) },
                    organizations: organizations.map { ContactsRepository.OrganizationDraft(name: $0.name, title: $0.title, department: $0.department, isCurrent: $0.isCurrent) },
                    urls: urls,
                    relations: relations,
                    userDefinedFields: userDefinedFields,
                    birthday: birthdayComponents,
                    notes: notes
                )
                _ = try environment.repository.createContact(draft)
            }
            dismiss()
        } catch {
            // Local SwiftData save failures are unexpected (disk full, etc.); surfaced via the
            // per-contact sync-error indicator is not applicable here since this is a save-time
            // failure, not a sync-time one, so a lightweight print suffices for v1.
            print("Failed to save contact: \(error)")
        }
    }
}
