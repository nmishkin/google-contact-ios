import SwiftUI
import SwiftData
import GoogleContactsKit

struct ContactListView: View {
    let filter: SidebarFilter
    @EnvironmentObject private var environment: AppEnvironment
    @Query(sort: [SortDescriptor(\Contact.familyName), SortDescriptor(\Contact.givenName)])
    private var allContacts: [Contact]
    @State private var searchText = ""
    @Binding var selectedContact: Contact?
    @State private var isPresentingNewContact = false

    private var filtered: [Contact] {
        let base = allContacts.filter { !$0.isDeletedLocally }
        let byFilter: [Contact]
        switch filter {
        case .all: byFilter = base
        case .starred: byFilter = base.filter(\.isStarred)
        case .peopleContacts: byFilter = base.filter { !$0.givenName.isEmpty && !$0.familyName.isEmpty }
        case .organizationContacts: byFilter = base.filter { $0.givenName.isEmpty && $0.familyName.isEmpty && !$0.organizations.isEmpty }
        case .group(let group): byFilter = base.filter { $0.memberships.contains { $0.resourceName == group.resourceName } }
        }
        guard !searchText.isEmpty else { return byFilter }
        return byFilter.filter { $0.matchesSearch(searchText) }
    }

    var body: some View {
        List(filtered, selection: $selectedContact) { contact in
            NavigationLink(value: contact) {
                ContactRow(contact: contact)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { try? environment.repository.delete(contact) } label: { Label("Delete", systemImage: "trash") }
            }
            .contactRowInsets()
        }
        #if os(iOS)
        .listRowSpacing(2)
        #endif
        .searchable(text: $searchText)
        .refreshable { try? await environment.repository.refresh() }
        .navigationTitle(title(for: filter))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNewContact = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $isPresentingNewContact) {
            ContactEditView { selectedContact = $0 }
        }
    }

    private func title(for filter: SidebarFilter) -> String {
        switch filter {
        case .all: "All Contacts"
        case .starred: "Starred"
        case .peopleContacts: "People Contacts"
        case .organizationContacts: "Organization Contacts"
        case .group(let group): group.name
        }
    }
}

extension Contact {
    /// Matches against every text field the contact model holds, not just name/email/phone, so a
    /// term found anywhere in the app (notes, an address, a custom field, ...) is also findable
    /// here.
    func matchesSearch(_ searchText: String) -> Bool {
        func contains(_ value: String) -> Bool { value.localizedCaseInsensitiveContains(searchText) }

        if contains(givenName) || contains(familyName) || contains(middleName)
            || contains(nickname) || contains(phoneticGivenName) || contains(phoneticFamilyName)
            || contains(notes) {
            return true
        }
        if emails.contains(where: { contains($0.value) }) { return true }
        if phones.contains(where: { contains($0.value) }) { return true }
        if urls.contains(where: { contains($0.value) }) { return true }
        if organizations.contains(where: { contains($0.name) || contains($0.title) || contains($0.department) }) { return true }
        if addresses.contains(where: {
            contains($0.street) || contains($0.city) || contains($0.region) || contains($0.postalCode) || contains($0.country) || contains($0.formattedValue)
        }) { return true }
        if relations.contains(where: { contains($0.label) || contains($0.value) }) { return true }
        if userDefinedFields.contains(where: { contains($0.label) || contains($0.value) }) { return true }
        return false
    }
}

/// One contact's row: name (family name bolded) with the organization as a subtitle.
struct ContactRow: View {
    let contact: Contact

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            primaryLabelText(for: contact)
                .font(.body)
            if let subtitle = organizationSubtitle(for: contact) {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func primaryLabel(for contact: Contact) -> String {
        let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        return contact.organizations.first?.name ?? ""
    }

    /// Bolds the family name when both a given and family name are present; otherwise renders
    /// the plain fallback label (full name with only one part, or the organization name).
    private func primaryLabelText(for contact: Contact) -> Text {
        let given = contact.givenName.trimmingCharacters(in: .whitespaces)
        let family = contact.familyName.trimmingCharacters(in: .whitespaces)
        guard !given.isEmpty, !family.isEmpty else {
            return Text(primaryLabel(for: contact))
        }
        return Text("\(given) ") + Text(family).bold()
    }

    /// Shows the organization name as a subtitle, unless it's already shown as the primary
    /// label (nameless contacts fall back to the organization name up top).
    private func organizationSubtitle(for contact: Contact) -> String? {
        let hasName = !"\(contact.givenName)\(contact.familyName)".trimmingCharacters(in: .whitespaces).isEmpty
        guard hasName, let organization = contact.organizations.first, !organization.name.isEmpty else { return nil }
        return organization.name
    }
}

extension View {
    func contactRowInsets() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}
