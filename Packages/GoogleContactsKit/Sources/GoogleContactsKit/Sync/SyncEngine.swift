import Foundation
import SwiftData

public protocol SyncTokenStoring: Sendable {
    func load() -> String?
    func save(_ token: String?)
}

public final class UserDefaultsSyncTokenStore: SyncTokenStoring, @unchecked Sendable {
    private let key = "GoogleContactsKit.syncToken"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> String? { defaults.string(forKey: key) }
    public func save(_ token: String?) { defaults.set(token, forKey: key) }
}

public actor SyncEngine {
    let modelContainer: ModelContainer
    let apiClient: PeopleAPIClientProtocol
    private let syncTokenStore: SyncTokenStoring
    let conflictRegistry = ConflictRegistry()

    public init(modelContainer: ModelContainer, apiClient: PeopleAPIClientProtocol, syncTokenStore: SyncTokenStoring = UserDefaultsSyncTokenStore()) {
        self.modelContainer = modelContainer
        self.apiClient = apiClient
        self.syncTokenStore = syncTokenStore
    }

    public func fullSync() async throws {
        let context = ModelContext(modelContainer)
        let groupsByResourceName = await syncGroups(context: context)

        var seenResourceNames = Set<String>()
        var pageToken: String? = nil
        var finalSyncToken: String? = nil
        repeat {
            let page = try await apiClient.listConnections(pageToken: pageToken, syncToken: nil)
            try upsert(connections: page.connections ?? [], groupsByResourceName: groupsByResourceName, context: context)
            seenResourceNames.formUnion((page.connections ?? []).map(\.resourceName))
            pageToken = page.nextPageToken?.isEmpty == false ? page.nextPageToken : nil
            if let token = page.nextSyncToken { finalSyncToken = token }
        } while pageToken != nil

        let allLocalContacts = try context.fetch(FetchDescriptor<Contact>())
        for contact in allLocalContacts where !seenResourceNames.contains(contact.resourceName) && !contact.isPendingCreate {
            context.delete(contact)
        }

        try context.save()
        if let finalSyncToken { syncTokenStore.save(finalSyncToken) }
    }

    public func incrementalSync() async throws {
        guard let syncToken = syncTokenStore.load() else {
            try await fullSync()
            return
        }
        let context = ModelContext(modelContainer)
        let groupsByResourceName = await syncGroups(context: context)

        var pageToken: String? = nil
        var finalSyncToken: String? = nil
        do {
            repeat {
                let page = try await apiClient.listConnections(pageToken: pageToken, syncToken: syncToken)
                for connection in page.connections ?? [] {
                    if connection.isDeleted {
                        if let existing = try context.fetch(FetchDescriptor<Contact>(predicate: #Predicate { $0.resourceName == connection.resourceName })).first {
                            context.delete(existing)
                        }
                    } else {
                        try upsert(connections: [connection], groupsByResourceName: groupsByResourceName, context: context)
                    }
                }
                pageToken = page.nextPageToken?.isEmpty == false ? page.nextPageToken : nil
                if let token = page.nextSyncToken { finalSyncToken = token }
            } while pageToken != nil
        } catch PeopleAPIError.expiredSyncToken {
            try await fullSync()
            return
        }

        try context.save()
        if let finalSyncToken { syncTokenStore.save(finalSyncToken) }
    }

    // Refreshes groups from the server and returns the current local groups (both new and
    // previously-known) keyed by resourceName. Called on every sync, not just fullSync, so that
    // labels created or renamed after the initial sync are still picked up by incrementalSync,
    // which otherwise never touches the groups endpoint at all.
    //
    // Best-effort: a groups-specific failure (e.g. insufficient scope for that endpoint) shouldn't
    // block syncing contacts, which is the primary thing users need; on failure this falls back to
    // whatever groups are already cached locally rather than losing membership data.
    private func syncGroups(context: ModelContext) async -> [String: ContactGroup] {
        let existingGroups = (try? context.fetch(FetchDescriptor<ContactGroup>())) ?? []
        var groupsByResourceName = Dictionary(uniqueKeysWithValues: existingGroups.map { ($0.resourceName, $0) })

        let groupDTOs: [ContactGroupDTO]
        do {
            groupDTOs = try await apiClient.listContactGroups()
        } catch {
            print("⚠️ listContactGroups failed, continuing with locally cached groups: \(error)")
            return groupsByResourceName
        }

        for dto in groupDTOs {
            if let group = groupsByResourceName[dto.resourceName] {
                group.name = dto.displayName
                group.groupType = dto.groupType
                group.etag = dto.etag ?? ""
            } else {
                let group = ContactGroup(resourceName: dto.resourceName, name: dto.displayName, groupType: dto.groupType, etag: dto.etag ?? "")
                context.insert(group)
                groupsByResourceName[dto.resourceName] = group
            }
        }
        return groupsByResourceName
    }

    private func upsert(connections: [ConnectionDTO], groupsByResourceName: [String: ContactGroup], context: ModelContext) throws {
        for connection in connections {
            let resourceName = connection.resourceName
            let existing = try context.fetch(FetchDescriptor<Contact>(predicate: #Predicate { $0.resourceName == resourceName })).first
            let contact = existing ?? Contact(resourceName: resourceName, etag: connection.etag ?? "", updateTime: .now)
            contact.apply(connection.asPerson, groupsByResourceName: groupsByResourceName)
            if existing == nil { context.insert(contact) }
        }
    }
}
