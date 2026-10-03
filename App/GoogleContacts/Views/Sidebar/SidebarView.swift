import SwiftUI
import SwiftData
import GoogleContactsKit

// #Predicate can't resolve a static-member keypath (ContactGroup.labelLikeSystemGroupResourceNames)
// inside the macro; capturing it as a plain top-level constant works.
private let labelLikeSystemGroups = ContactGroup.labelLikeSystemGroupResourceNames

struct SidebarView: View {
    // "starred" already has its own dedicated sidebar entry above.
    @Query(filter: #Predicate<ContactGroup> {
        $0.groupType == "USER_CONTACT_GROUP" || labelLikeSystemGroups.contains($0.resourceName)
    }, sort: \ContactGroup.name)
    private var labels: [ContactGroup]
    @Binding var selection: SidebarFilter
    @Environment(\.signOut) private var signOut
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: [SortDescriptor(\Contact.familyName), SortDescriptor(\Contact.givenName)])
    private var allContacts: [Contact]
    @State private var searchText = ""
    @State private var searchSelectedContact: Contact?
    #endif

    // SwiftUI's `List(selection:)` overload taking a non-optional binding is macOS-only; iOS
    // requires `Binding<SelectionValue?>`. This wraps/unwraps so the public API here stays a
    // plain non-optional `SidebarFilter` binding for callers.
    private var optionalSelection: Binding<SidebarFilter?> {
        Binding(get: { selection }, set: { if let newValue = $0 { selection = newValue } })
    }

    var body: some View {
        #if os(iOS)
        // On iPhone the sidebar is the first screen, so it gets a search box over all contacts
        // (the contact list's own search only covers the current filter, one screen deeper).
        if horizontalSizeClass == .compact {
            filterList
                .searchable(text: $searchText, prompt: "Search All Contacts")
                .navigationDestination(item: $searchSelectedContact) { contact in
                    ContactDetailView(contact: contact, selectedContact: $searchSelectedContact)
                }
        } else {
            filterList
        }
        #else
        filterList
        #endif
    }

    private var filterList: some View {
        List(selection: optionalSelection) {
            #if os(iOS)
            if !searchText.isEmpty {
                searchResults
            } else {
                filterRows
            }
            #else
            filterRows
            #endif
        }
        #if os(iOS)
        .listRowSpacing(2)
        #endif
        .navigationTitle("Google Contacts")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Sign Out", role: .destructive, action: signOut)
            }
        }
    }

    @ViewBuilder
    private var filterRows: some View {
        Label("All Contacts", systemImage: "person.2").tag(SidebarFilter.all)
        Label("People Contacts", systemImage: "person").tag(SidebarFilter.peopleContacts)
        Label("Organization Contacts", systemImage: "building.2").tag(SidebarFilter.organizationContacts)
        Label("Starred", systemImage: "star.fill").tag(SidebarFilter.starred)
        Section("Labels") {
            ForEach(labels) { group in
                Label(group.name, systemImage: "tag").tag(SidebarFilter.group(group))
            }
            NavigationLink("Edit Labels") { LabelsManagementView() }
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var searchResults: some View {
        let results = allContacts.filter { !$0.isDeletedLocally && $0.matchesSearch(searchText) }
        if results.isEmpty {
            Text("No matching contacts").foregroundStyle(.secondary)
        } else {
            ForEach(results) { contact in
                Button { searchSelectedContact = contact } label: {
                    ContactRow(contact: contact).foregroundStyle(.primary)
                }
                .contactRowInsets()
            }
        }
    }
    #endif
}
