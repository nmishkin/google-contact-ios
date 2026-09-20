import SwiftUI
import SwiftData
import GoogleContactsKit

struct SidebarView: View {
    @Query(filter: #Predicate<ContactGroup> { $0.groupType == "USER_CONTACT_GROUP" }, sort: \ContactGroup.name)
    private var labels: [ContactGroup]
    @Binding var selection: SidebarFilter
    @Environment(\.signOut) private var signOut

    // SwiftUI's `List(selection:)` overload taking a non-optional binding is macOS-only; iOS
    // requires `Binding<SelectionValue?>`. This wraps/unwraps so the public API here stays a
    // plain non-optional `SidebarFilter` binding for callers.
    private var optionalSelection: Binding<SidebarFilter?> {
        Binding(get: { selection }, set: { if let newValue = $0 { selection = newValue } })
    }

    var body: some View {
        List(selection: optionalSelection) {
            Label("All Contacts", systemImage: "person.2").tag(SidebarFilter.all)
            Label("Starred", systemImage: "star.fill").tag(SidebarFilter.starred)
            Section("Labels") {
                ForEach(labels) { group in
                    Label(group.name, systemImage: "tag").tag(SidebarFilter.group(group))
                }
                NavigationLink("Edit Labels") { LabelsManagementView() }
            }
        }
        .navigationTitle("Google Contacts")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Sign Out", role: .destructive, action: signOut)
            }
        }
    }
}
