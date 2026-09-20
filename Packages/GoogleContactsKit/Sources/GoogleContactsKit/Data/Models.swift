import Foundation
import SwiftData

@Model
public final class Contact {
    @Attribute(.unique) public var resourceName: String
    public var etag: String
    public var updateTime: Date

    public var givenName: String = ""
    public var familyName: String = ""
    public var middleName: String = ""
    public var phoneticGivenName: String = ""
    public var phoneticFamilyName: String = ""
    public var nickname: String = ""
    public var photoURL: String?
    public var notes: String = ""

    // SwiftData can't persist `DateComponents` directly (its embedded `Calendar` reference isn't
    // a storable property type), so the partial birthday is stored as three plain optional Ints
    // and exposed as `DateComponents` through this computed property.
    public var birthYear: Int?
    public var birthMonth: Int?
    public var birthDay: Int?

    public var birthday: DateComponents? {
        get {
            guard birthYear != nil || birthMonth != nil || birthDay != nil else { return nil }
            return DateComponents(year: birthYear, month: birthMonth, day: birthDay)
        }
        set {
            birthYear = newValue?.year
            birthMonth = newValue?.month
            birthDay = newValue?.day
        }
    }

    @Relationship(deleteRule: .cascade) public var emails: [LabeledValue] = []
    @Relationship(deleteRule: .cascade) public var phones: [LabeledValue] = []
    @Relationship(deleteRule: .cascade) public var addresses: [PostalAddress] = []
    @Relationship(deleteRule: .cascade) public var organizations: [Organization] = []
    @Relationship(deleteRule: .cascade) public var urls: [LabeledValue] = []
    @Relationship(deleteRule: .cascade) public var relations: [LabeledValue] = []
    @Relationship(deleteRule: .cascade) public var userDefinedFields: [LabeledValue] = []
    @Relationship public var memberships: [ContactGroup] = []

    public var isPendingCreate: Bool = false
    public var isDeletedLocally: Bool = false

    public init(resourceName: String, etag: String, updateTime: Date) {
        self.resourceName = resourceName
        self.etag = etag
        self.updateTime = updateTime
    }

    /// True iff this contact is a member of Google's built-in "starred" system group.
    public var isStarred: Bool {
        memberships.contains { $0.resourceName == "contactGroups/starred" }
    }
}

@Model
public final class LabeledValue {
    public var label: String
    public var value: String
    public var isPrimary: Bool

    public init(label: String, value: String, isPrimary: Bool) {
        self.label = label
        self.value = value
        self.isPrimary = isPrimary
    }
}

@Model
public final class PostalAddress {
    public var label: String = ""
    public var street: String = ""
    public var city: String = ""
    public var region: String = ""
    public var postalCode: String = ""
    public var country: String = ""
    public var formattedValue: String = ""

    public init(label: String = "", street: String = "", city: String = "", region: String = "", postalCode: String = "", country: String = "", formattedValue: String = "") {
        self.label = label
        self.street = street
        self.city = city
        self.region = region
        self.postalCode = postalCode
        self.country = country
        self.formattedValue = formattedValue
    }
}

@Model
public final class Organization {
    public var name: String = ""
    public var title: String = ""
    public var department: String = ""
    public var isCurrent: Bool = false

    public init(name: String = "", title: String = "", department: String = "", isCurrent: Bool = false) {
        self.name = name
        self.title = title
        self.department = department
        self.isCurrent = isCurrent
    }
}

@Model
public final class ContactGroup {
    @Attribute(.unique) public var resourceName: String
    public var etag: String = ""
    public var name: String
    public var groupType: String // "USER_CONTACT_GROUP" or "SYSTEM_CONTACT_GROUP"
    @Relationship(inverse: \Contact.memberships) public var members: [Contact] = []

    public init(resourceName: String, name: String, groupType: String, etag: String = "") {
        self.resourceName = resourceName
        self.name = name
        self.groupType = groupType
        self.etag = etag
    }
}

public enum MutationKind: Codable, Equatable {
    case create
    case update(fieldMask: String)
    case delete
    case groupMembershipChange
}

@Model
public final class PendingMutation {
    public var id: UUID
    public var kind: MutationKind
    public var targetResourceName: String?
    public var payload: Data
    public var createdAt: Date
    public var retryCount: Int = 0
    public var lastError: String?

    public init(id: UUID = UUID(), kind: MutationKind, targetResourceName: String?, payload: Data, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.targetResourceName = targetResourceName
        self.payload = payload
        self.createdAt = createdAt
    }
}
