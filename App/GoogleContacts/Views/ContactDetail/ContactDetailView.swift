import SwiftUI
import GoogleContactsKit

struct ContactDetailView: View {
    let contact: Contact
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isEditing = false
    @State private var hasConflict = false

    var body: some View {
        Form {
            if hasConflict {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This contact changed elsewhere").font(.headline)
                        HStack {
                            Button("Keep mine") { Task { try? await environment.syncEngine.resolveConflict(resourceName: contact.resourceName, keepLocal: true); hasConflict = false } }
                            Button("Use theirs") { Task { try? await environment.syncEngine.resolveConflict(resourceName: contact.resourceName, keepLocal: false); hasConflict = false } }
                        }
                    }
                }
            }

            Section("Name") {
                Text("\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces))
                if !contact.nickname.isEmpty { LabeledContent("Nickname", value: contact.nickname) }
            }
            if !contact.emails.isEmpty {
                Section("Email") { ForEach(contact.emails) { LabeledContent($0.label.capitalized, value: $0.value) } }
            }
            if !contact.phones.isEmpty {
                Section("Phone") { ForEach(contact.phones) { LabeledContent($0.label.capitalized, value: $0.value) } }
            }
            if !contact.addresses.isEmpty {
                Section("Address") {
                    ForEach(contact.addresses) { address in
                        Text(address.formattedValue.isEmpty ? [address.street, address.city, address.region, address.postalCode, address.country].filter { !$0.isEmpty }.joined(separator: ", ") : address.formattedValue)
                    }
                }
            }
            if !contact.organizations.isEmpty {
                Section("Organization") {
                    ForEach(contact.organizations) { org in
                        VStack(alignment: .leading) {
                            Text(org.name)
                            if !org.title.isEmpty { Text(org.title).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if let birthday = contact.birthday {
                Section("Birthday") { Text(formatted(birthday)) }
            }
            if !contact.urls.isEmpty {
                Section("Links") { ForEach(contact.urls) { LabeledContent($0.label.capitalized, value: $0.value) } }
            }
            if !contact.userDefinedFields.isEmpty {
                Section("Custom Fields") { ForEach(contact.userDefinedFields) { LabeledContent($0.label, value: $0.value) } }
            }
            if !contact.notes.isEmpty {
                Section("Notes") { Text(contact.notes) }
            }
        }
        .navigationTitle("\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces))
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            ContactEditView(contact: contact)
        }
        .task(id: contact.resourceName) {
            let conflicts = await environment.syncEngine.pendingConflicts()
            hasConflict = conflicts.contains { $0.resourceName == contact.resourceName }
        }
    }

    private func formatted(_ components: DateComponents) -> String {
        var parts: [String] = []
        if let month = components.month, let day = components.day {
            parts.append(DateFormatter().monthSymbols[month - 1] + " \(day)")
        }
        if let year = components.year { parts.append(String(year)) }
        return parts.joined(separator: ", ")
    }
}

extension LabeledValue: Identifiable {}
extension PostalAddress: Identifiable {}
extension Organization: Identifiable {}
