import SwiftUI
import GoogleContactsKit

struct ContactDetailView: View {
    let contact: Contact
    @Binding var selectedContact: Contact?
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isEditing = false
    @State private var hasConflict = false
    @State private var isConfirmingDelete = false

    private var displayName: String {
        let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "this contact" : name
    }

    // Excludes pure-infrastructure system groups (myContacts, all, chatBuddies, blocked) that
    // aren't user-facing labels; "starred" is already shown via the star indicator elsewhere.
    // Matches the set SidebarView and ContactEditView treat as assignable labels.
    private var labels: [ContactGroup] {
        contact.memberships
            .filter { $0.groupType == "USER_CONTACT_GROUP" || ContactGroup.labelLikeSystemGroupResourceNames.contains($0.resourceName) }
            .sorted { $0.name < $1.name }
    }

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
                Section("Phone") {
                    ForEach(contact.phones) { phone in
                        if let url = telURL(for: phone.value) {
                            LabeledContent(phone.label.capitalized) { Link(phone.value, destination: url) }
                        } else {
                            LabeledContent(phone.label.capitalized, value: phone.value)
                        }
                    }
                }
            }
            if !contact.addresses.isEmpty {
                Section("Address") {
                    ForEach(contact.addresses) { address in
                        let text = displayText(for: address)
                        if let appleURL = appleMapsURL(for: text), let googleURL = googleMapsURL(for: text) {
                            Menu {
                                Link("Open in Apple Maps", destination: appleURL)
                                Link("Open in Google Maps", destination: googleURL)
                            } label: {
                                // Menus in a Form render like buttons, which center multi-line text.
                                Text(text)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(.tint)
                                    .contentShape(Rectangle())
                            }
                            .menuStyle(.button)
                            // .borderless ignores the label's foreground style on macOS (renders black).
                            .buttonStyle(.plain)
                            .menuIndicator(.hidden)
                        } else {
                            Text(text)
                        }
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
            if !labels.isEmpty {
                Section("Labels") {
                    ForEach(labels) { group in
                        Label(group.name, systemImage: "tag")
                    }
                }
            }
            if !contact.notes.isEmpty {
                Section("Notes") { Text(contact.notes) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces))
        .toolbar {
            Button("Edit") { isEditing = true }
            Button("Delete", role: .destructive) { isConfirmingDelete = true }
        }
        .sheet(isPresented: $isEditing) {
            ContactEditView(contact: contact)
        }
        .confirmationDialog("Delete \(displayName)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteContact() }
        } message: {
            Text("This removes \(displayName) from your Google Contacts. This can't be undone.")
        }
        .task(id: contact.resourceName) {
            let conflicts = await environment.syncEngine.pendingConflicts()
            hasConflict = conflicts.contains { $0.resourceName == contact.resourceName }
        }
    }

    private func deleteContact() {
        try? environment.repository.delete(contact)
        selectedContact = nil
    }

    private func displayText(for address: PostalAddress) -> String {
        address.formattedValue.isEmpty ? [address.street, address.city, address.region, address.postalCode, address.country].filter { !$0.isEmpty }.joined(separator: ", ") : address.formattedValue
    }

    // Apple Maps universal link: opens the Maps app on iOS/macOS and searches for the address.
    private func appleMapsURL(for address: String) -> URL? {
        searchURL("https://maps.apple.com/", queryName: "q", address: address)
    }

    // Google Maps universal link: opens the Google Maps app on iOS if installed, otherwise the
    // browser (always the browser on macOS, which has no Google Maps app).
    private func googleMapsURL(for address: String) -> URL? {
        searchURL("https://www.google.com/maps/search/?api=1", queryName: "query", address: address)
    }

    private func searchURL(_ base: String, queryName: String, address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: base) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: queryName, value: trimmed)]
        return components.url
    }

    // tel: URLs only accept dialable characters, so drop formatting like spaces, dashes and parens.
    private func telURL(for phone: String) -> URL? {
        let dialable = phone.filter { $0.isNumber || "+*#,;".contains($0) }
        guard dialable.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel:\(dialable)")
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
