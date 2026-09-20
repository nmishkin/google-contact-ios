import SwiftUI
import GoogleContactsKit

struct RootSplitView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selectedContact: Contact?
    @StateObject private var networkMonitor = NetworkStatusMonitor()

    var body: some View {
        VStack(spacing: 0) {
            OfflineBannerView(monitor: networkMonitor)
            NavigationSplitView {
                SidebarView(selection: $environment.selectedFilter)
            } content: {
                ContactListView(filter: environment.selectedFilter, selectedContact: $selectedContact)
            } detail: {
                if let selectedContact {
                    ContactDetailView(contact: selectedContact)
                } else {
                    ContentUnavailableView("Select a contact", systemImage: "person.crop.circle")
                }
            }
        }
        .onAppear { environment.syncOnForeground() }
    }
}
