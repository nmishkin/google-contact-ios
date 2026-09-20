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
        return byFilter.filter {
            $0.givenName.localizedCaseInsensitiveContains(searchText)
            || $0.familyName.localizedCaseInsensitiveContains(searchText)
            || $0.emails.contains { $0.value.localizedCaseInsensitiveContains(searchText) }
            || $0.phones.contains { $0.value.localizedCaseInsensitiveContains(searchText) }
            || $0.organizations.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        List(filtered, selection: $selectedContact) { contact in
            NavigationLink(value: contact) {
                VStack(alignment: .leading) {
                    Text(primaryLabel(for: contact))
                        .font(.body)
                    if let subtitle = organizationSubtitle(for: contact) {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { try? environment.repository.delete(contact) } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .searchable(text: $searchText)
        .refreshable { try? await environment.repository.refresh() }
        .navigationTitle(title(for: filter))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNewContact = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $isPresentingNewContact) {
            ContactEditView()
        }
    }

    private func primaryLabel(for contact: Contact) -> String {
        let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        return contact.organizations.first?.name ?? ""
    }

    /// Shows the organization name as a subtitle, unless it's already shown as the primary
    /// label (nameless contacts fall back to the organization name up top).
    private func organizationSubtitle(for contact: Contact) -> String? {
        let hasName = !"\(contact.givenName)\(contact.familyName)".trimmingCharacters(in: .whitespaces).isEmpty
        guard hasName, let organization = contact.organizations.first, !organization.name.isEmpty else { return nil }
        return organization.name
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
