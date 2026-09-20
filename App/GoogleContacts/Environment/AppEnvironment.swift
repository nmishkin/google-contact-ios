import Foundation
import SwiftData
import GoogleContactsKit

enum SidebarFilter: Hashable {
    case all
    case starred
    case peopleContacts
    case organizationContacts
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

    /// Wipes all locally cached Google data. Called on sign-out per the design spec: Google's
    /// data shouldn't linger locally once signed out.
    func wipeLocalData() throws {
        let context = modelContainer.mainContext
        try context.delete(model: PendingMutation.self)
        try context.delete(model: Contact.self) // cascades to emails/phones/addresses/etc.
        try context.delete(model: ContactGroup.self)
        try context.save()
    }

    func syncOnForeground() {
        Task {
            do {
                try await syncEngine.incrementalSync()
            } catch {
                print("⚠️ incrementalSync failed: \(error)")
            }
            do {
                try await syncEngine.drainOutbox()
            } catch {
                print("⚠️ drainOutbox failed: \(error)")
            }
        }
    }
}
