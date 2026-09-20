import Foundation

public struct FieldMetadataDTO: Codable, Equatable, Sendable {
    public var primary: Bool?

    public init(primary: Bool? = nil) {
        self.primary = primary
    }
}

public struct NameDTO: Codable, Equatable, Sendable {
    public var metadata: FieldMetadataDTO?
    public var givenName: String?
    public var familyName: String?
    public var middleName: String?
    public var phoneticGivenName: String?
    public var phoneticFamilyName: String?

    public init(metadata: FieldMetadataDTO? = nil, givenName: String? = nil, familyName: String? = nil, middleName: String? = nil, phoneticGivenName: String? = nil, phoneticFamilyName: String? = nil) {
        self.metadata = metadata
        self.givenName = givenName
        self.familyName = familyName
        self.middleName = middleName
        self.phoneticGivenName = phoneticGivenName
        self.phoneticFamilyName = phoneticFamilyName
    }
}

public struct NicknameDTO: Codable, Equatable, Sendable {
    public var value: String?

    public init(value: String? = nil) {
        self.value = value
    }
}

/// Covers emailAddresses, phoneNumbers, urls, and relations — all share this shape in the People API.
public struct LabeledStringDTO: Codable, Equatable, Sendable {
    public var metadata: FieldMetadataDTO?
    public var value: String?
    public var type: String?
    public var person: String? // only present on `relations`

    public init(metadata: FieldMetadataDTO? = nil, value: String? = nil, type: String? = nil, person: String? = nil) {
        self.metadata = metadata
        self.value = value
        self.type = type
        self.person = person
    }
}

public struct AddressDTO: Codable, Equatable, Sendable {
    public var metadata: FieldMetadataDTO?
    public var type: String?
    public var streetAddress: String?
    public var city: String?
    public var region: String?
    public var postalCode: String?
    public var country: String?
    public var formattedValue: String?

    public init(metadata: FieldMetadataDTO? = nil, type: String? = nil, streetAddress: String? = nil, city: String? = nil, region: String? = nil, postalCode: String? = nil, country: String? = nil, formattedValue: String? = nil) {
        self.metadata = metadata
        self.type = type
        self.streetAddress = streetAddress
        self.city = city
        self.region = region
        self.postalCode = postalCode
        self.country = country
        self.formattedValue = formattedValue
    }
}

public struct OrganizationDTO: Codable, Equatable, Sendable {
    public var metadata: FieldMetadataDTO?
    public var name: String?
    public var title: String?
    public var department: String?
    public var current: Bool?

    public init(metadata: FieldMetadataDTO? = nil, name: String? = nil, title: String? = nil, department: String? = nil, current: Bool? = nil) {
        self.metadata = metadata
        self.name = name
        self.title = title
        self.department = department
        self.current = current
    }
}

public struct UserDefinedFieldDTO: Codable, Equatable, Sendable {
    public var key: String?
    public var value: String?

    public init(key: String? = nil, value: String? = nil) {
        self.key = key
        self.value = value
    }
}

public struct PartialDateDTO: Codable, Equatable, Sendable {
    public var year: Int?
    public var month: Int?
    public var day: Int?

    public init(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
    }
}

public struct BirthdayDTO: Codable, Equatable, Sendable {
    public var metadata: FieldMetadataDTO?
    public var date: PartialDateDTO?

    public init(metadata: FieldMetadataDTO? = nil, date: PartialDateDTO? = nil) {
        self.metadata = metadata
        self.date = date
    }
}

public struct BiographyDTO: Codable, Equatable, Sendable {
    public var value: String?

    public init(value: String? = nil) {
        self.value = value
    }
}

public struct ContactGroupMembershipDTO: Codable, Equatable, Sendable {
    public var contactGroupResourceName: String

    public init(contactGroupResourceName: String) {
        self.contactGroupResourceName = contactGroupResourceName
    }
}

public struct MembershipDTO: Codable, Equatable, Sendable {
    public var contactGroupMembership: ContactGroupMembershipDTO

    public init(contactGroupMembership: ContactGroupMembershipDTO) {
        self.contactGroupMembership = contactGroupMembership
    }
}

public struct PhotoDTO: Codable, Equatable, Sendable {
    public var url: String?
    public var metadata: FieldMetadataDTO?

    public init(url: String? = nil, metadata: FieldMetadataDTO? = nil) {
        self.url = url
        self.metadata = metadata
    }
}

public struct PersonDTO: Codable, Equatable, Sendable {
    public var resourceName: String
    public var etag: String
    public var names: [NameDTO]?
    public var nicknames: [NicknameDTO]?
    public var emailAddresses: [LabeledStringDTO]?
    public var phoneNumbers: [LabeledStringDTO]?
    public var addresses: [AddressDTO]?
    public var organizations: [OrganizationDTO]?
    public var urls: [LabeledStringDTO]?
    public var relations: [LabeledStringDTO]?
    public var userDefined: [UserDefinedFieldDTO]?
    public var birthdays: [BirthdayDTO]?
    public var biographies: [BiographyDTO]?
    public var memberships: [MembershipDTO]?
    public var photos: [PhotoDTO]?

    public init(resourceName: String, etag: String, names: [NameDTO]? = nil, nicknames: [NicknameDTO]? = nil, emailAddresses: [LabeledStringDTO]? = nil, phoneNumbers: [LabeledStringDTO]? = nil, addresses: [AddressDTO]? = nil, organizations: [OrganizationDTO]? = nil, urls: [LabeledStringDTO]? = nil, relations: [LabeledStringDTO]? = nil, userDefined: [UserDefinedFieldDTO]? = nil, birthdays: [BirthdayDTO]? = nil, biographies: [BiographyDTO]? = nil, memberships: [MembershipDTO]? = nil, photos: [PhotoDTO]? = nil) {
        self.resourceName = resourceName
        self.etag = etag
        self.names = names
        self.nicknames = nicknames
        self.emailAddresses = emailAddresses
        self.phoneNumbers = phoneNumbers
        self.addresses = addresses
        self.organizations = organizations
        self.urls = urls
        self.relations = relations
        self.userDefined = userDefined
        self.birthdays = birthdays
        self.biographies = biographies
        self.memberships = memberships
        self.photos = photos
    }
}

public struct PersonMetadataDeletedDTO: Codable, Equatable, Sendable {
    public var deleted: Bool?

    public init(deleted: Bool? = nil) {
        self.deleted = deleted
    }
}

/// A connection list entry can additionally carry deletion metadata when returned from an
/// incremental (syncToken) sync.
public struct ConnectionDTO: Codable, Equatable, Sendable {
    public var resourceName: String
    public var etag: String?
    public var metadata: PersonMetadataDeletedDTO?
    public var names: [NameDTO]?
    public var nicknames: [NicknameDTO]?
    public var emailAddresses: [LabeledStringDTO]?
    public var phoneNumbers: [LabeledStringDTO]?
    public var addresses: [AddressDTO]?
    public var organizations: [OrganizationDTO]?
    public var urls: [LabeledStringDTO]?
    public var relations: [LabeledStringDTO]?
    public var userDefined: [UserDefinedFieldDTO]?
    public var birthdays: [BirthdayDTO]?
    public var biographies: [BiographyDTO]?
    public var memberships: [MembershipDTO]?
    public var photos: [PhotoDTO]?

    public init(resourceName: String, etag: String? = nil, metadata: PersonMetadataDeletedDTO? = nil, names: [NameDTO]? = nil, nicknames: [NicknameDTO]? = nil, emailAddresses: [LabeledStringDTO]? = nil, phoneNumbers: [LabeledStringDTO]? = nil, addresses: [AddressDTO]? = nil, organizations: [OrganizationDTO]? = nil, urls: [LabeledStringDTO]? = nil, relations: [LabeledStringDTO]? = nil, userDefined: [UserDefinedFieldDTO]? = nil, birthdays: [BirthdayDTO]? = nil, biographies: [BiographyDTO]? = nil, memberships: [MembershipDTO]? = nil, photos: [PhotoDTO]? = nil) {
        self.resourceName = resourceName
        self.etag = etag
        self.metadata = metadata
        self.names = names
        self.nicknames = nicknames
        self.emailAddresses = emailAddresses
        self.phoneNumbers = phoneNumbers
        self.addresses = addresses
        self.organizations = organizations
        self.urls = urls
        self.relations = relations
        self.userDefined = userDefined
        self.birthdays = birthdays
        self.biographies = biographies
        self.memberships = memberships
        self.photos = photos
    }

    public var isDeleted: Bool { metadata?.deleted == true }

    public var asPerson: PersonDTO {
        PersonDTO(resourceName: resourceName, etag: etag ?? "", names: names, nicknames: nicknames, emailAddresses: emailAddresses, phoneNumbers: phoneNumbers, addresses: addresses, organizations: organizations, urls: urls, relations: relations, userDefined: userDefined, birthdays: birthdays, biographies: biographies, memberships: memberships, photos: photos)
    }
}

public struct ListConnectionsResponseDTO: Codable, Equatable, Sendable {
    public var connections: [ConnectionDTO]?
    public var nextPageToken: String?
    public var nextSyncToken: String?
    public var totalItems: Int?

    public init(connections: [ConnectionDTO]? = nil, nextPageToken: String? = nil, nextSyncToken: String? = nil, totalItems: Int? = nil) {
        self.connections = connections
        self.nextPageToken = nextPageToken
        self.nextSyncToken = nextSyncToken
        self.totalItems = totalItems
    }
}

public struct ContactGroupDTO: Codable, Equatable, Sendable {
    public var resourceName: String
    public var etag: String
    public var name: String
    public var formattedName: String?
    public var groupType: String
    public var memberCount: Int?

    public init(resourceName: String, etag: String, name: String, formattedName: String? = nil, groupType: String, memberCount: Int? = nil) {
        self.resourceName = resourceName
        self.etag = etag
        self.name = name
        self.formattedName = formattedName
        self.groupType = groupType
        self.memberCount = memberCount
    }
}

public struct ListContactGroupsResponseDTO: Codable, Equatable, Sendable {
    public var contactGroups: [ContactGroupDTO]
    public var nextPageToken: String?

    public init(contactGroups: [ContactGroupDTO], nextPageToken: String? = nil) {
        self.contactGroups = contactGroups
        self.nextPageToken = nextPageToken
    }
}
