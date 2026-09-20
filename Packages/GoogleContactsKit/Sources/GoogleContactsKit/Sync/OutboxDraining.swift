import Foundation
import SwiftData

extension SyncEngine {
    public struct ConflictSnapshot: Sendable {
        public let resourceName: String
        public let serverCopy: PersonDTO
    }
}

/// Per-actor conflict state. Stored as a plain actor-isolated property is not possible via
/// extension (extensions can't add stored properties), so conflicts live in a small side actor
/// owned by SyncEngine instead.
public actor ConflictRegistry {
    private var conflicts: [String: SyncEngine.ConflictSnapshot] = [:]
    func record(_ conflict: SyncEngine.ConflictSnapshot) { conflicts[conflict.resourceName] = conflict }
    func clear(resourceName: String) { conflicts.removeValue(forKey: resourceName) }
    func all() -> [SyncEngine.ConflictSnapshot] { Array(conflicts.values) }
}

extension SyncEngine {
    public func drainOutbox() async throws {
        let context = ModelContext(modelContainer)
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.createdAt)]))

        for mutation in mutations {
            do {
                try await apply(mutation, context: context)
                context.delete(mutation)
            } catch PeopleAPIError.etagMismatch(let serverCopy) {
                await conflictRegistry.record(.init(resourceName: mutation.targetResourceName ?? "", serverCopy: serverCopy))
                // mutation stays queued; do not increment retryCount for conflicts, they need a decision, not a retry.
            } catch {
                mutation.retryCount += 1
                mutation.lastError = String(describing: error)
            }
        }
        try context.save()
    }

    public func pendingConflicts() async -> [ConflictSnapshot] {
        await conflictRegistry.all()
    }

    public func resolveConflict(resourceName: String, keepLocal: Bool) async throws {
        let context = ModelContext(modelContainer)
        guard let contact = try context.fetch(FetchDescriptor<Contact>(predicate: #Predicate { $0.resourceName == resourceName })).first else { return }
        guard let conflict = await conflictRegistry.all().first(where: { $0.resourceName == resourceName }) else { return }

        if keepLocal {
            contact.etag = conflict.serverCopy.etag // adopt the fresh etag so the retried push succeeds
            _ = try await apiClient.updateContact(contact.asPersonDTO, updateFieldMask: Contact.fieldMask(changedFrom: conflict.serverCopy, to: contact.asPersonDTO))
            let mutations = try context.fetch(FetchDescriptor<PendingMutation>(predicate: #Predicate { $0.targetResourceName == resourceName }))
            for mutation in mutations { context.delete(mutation) }
        } else {
            contact.apply(conflict.serverCopy, groupsByResourceName: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ContactGroup>()).map { ($0.resourceName, $0) }))
            let mutations = try context.fetch(FetchDescriptor<PendingMutation>(predicate: #Predicate { $0.targetResourceName == resourceName }))
            for mutation in mutations { context.delete(mutation) }
        }
        await conflictRegistry.clear(resourceName: resourceName)
        try context.save()
    }

    private func apply(_ mutation: PendingMutation, context: ModelContext) async throws {
        switch mutation.kind {
        case .create:
            guard let resourceName = mutation.targetResourceName,
                  let contact = try context.fetch(FetchDescriptor<Contact>(predicate: #Predicate { $0.resourceName == resourceName })).first else { return }
            let created = try await apiClient.createContact(contact.asPersonDTO)
            contact.resourceName = created.resourceName
            contact.etag = created.etag
            contact.isPendingCreate = false

        case .update(let fieldMask):
            guard let resourceName = mutation.targetResourceName,
                  let contact = try context.fetch(FetchDescriptor<Contact>(predicate: #Predicate { $0.resourceName == resourceName })).first else { return }
            let updated = try await apiClient.updateContact(contact.asPersonDTO, updateFieldMask: fieldMask)
            contact.etag = updated.etag

        case .delete:
            guard let resourceName = mutation.targetResourceName else { return }
            try await apiClient.deleteContact(resourceName: resourceName)
            if let contact = try context.fetch(FetchDescriptor<Contact>(predicate: #Predicate { $0.resourceName == resourceName })).first {
                context.delete(contact)
            }

        case .groupMembershipChange:
            guard let resourceName = mutation.targetResourceName else { return }
            let change = try JSONDecoder().decode(GroupMembershipChangePayload.self, from: mutation.payload)
            try await apiClient.modifyGroupMembers(groupResourceName: change.groupResourceName, add: change.add ? [resourceName] : [], remove: change.add ? [] : [resourceName])
        }
    }
}

struct GroupMembershipChangePayload: Codable {
    let groupResourceName: String
    let add: Bool
}
