import Foundation
import SwiftData
import GoogleContactsKit

enum SidebarFilter: Hashable {
    case all
    case starred
    case group(ContactGroup)
}

@MainActor
final class AppEnvironment: ObservableObject {
    let modelContainer: ModelContainer
    let syncEngine: SyncEngine
    let repository: ContactsRepository
    @Published var selectedFilter: SidebarFilter = .all

    init(auth: AuthTokenProviding, apiClientOverride: PeopleAPIClientProtocol? = nil) {
        let schema = Schema([Contact.self, LabeledValue.self, PostalAddress.self, Organization.self, ContactGroup.self, PendingMutation.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        let apiClient = apiClientOverride ?? PeopleAPIClient(auth: auth)
        let engine = SyncEngine(modelContainer: container, apiClient: apiClient)
        self.modelContainer = container
        self.syncEngine = engine
        self.repository = ContactsRepository(modelContainer: container, syncEngine: engine, apiClient: apiClient)
    }

    func syncOnForeground() {
        Task {
            try? await syncEngine.incrementalSync()
            try? await syncEngine.drainOutbox()
        }
    }
}
