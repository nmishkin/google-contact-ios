import SwiftUI
import GoogleContactsKit

struct ContactEditView: View {
    /// Pass an existing contact to edit it, or `nil` to create a new one.
    let existingContact: Contact?
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var givenName = ""
    @State private var familyName = ""
    @State private var notes = ""
    @State private var emails: [(label: String, value: String)] = []
    @State private var phones: [(label: String, value: String)] = []
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
            }
            .navigationTitle(existingContact == nil ? "New Contact" : "Edit Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: populateFromExistingContact)
        }
    }

    private func populateFromExistingContact() {
        guard let contact = existingContact else { return }
        givenName = contact.givenName
        familyName = contact.familyName
        notes = contact.notes
        emails = contact.emails.map { (label: $0.label, value: $0.value) }
        phones = contact.phones.map { (label: $0.label, value: $0.value) }
        previousSnapshot = contact.asPersonDTO
    }

    private func save() {
        do {
            if let contact = existingContact, let previousSnapshot {
                contact.givenName = givenName
                contact.familyName = familyName
                contact.notes = notes
                contact.emails = emails.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
                contact.phones = phones.map { LabeledValue(label: $0.label, value: $0.value, isPrimary: false) }
                try environment.repository.save(edit: contact, previousSnapshot: previousSnapshot)
            } else {
                let draft = ContactsRepository.ContactDraft(givenName: givenName, familyName: familyName, emails: emails, phones: phones, notes: notes)
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
