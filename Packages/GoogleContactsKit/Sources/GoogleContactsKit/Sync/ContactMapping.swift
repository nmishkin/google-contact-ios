import Foundation

extension Contact {
    /// Overwrites local fields from a server-provided DTO. `groupsByResourceName` must already
    /// contain every group this person references (SyncEngine syncs groups before contacts).
    public func apply(_ person: PersonDTO, groupsByResourceName: [String: ContactGroup]) {
        etag = person.etag
        updateTime = .now

        let primaryName = person.names?.first { $0.metadata?.primary == true } ?? person.names?.first
        givenName = primaryName?.givenName ?? ""
        familyName = primaryName?.familyName ?? ""
        middleName = primaryName?.middleName ?? ""
        phoneticGivenName = primaryName?.phoneticGivenName ?? ""
        phoneticFamilyName = primaryName?.phoneticFamilyName ?? ""
        nickname = person.nicknames?.first?.value ?? ""
        notes = person.biographies?.first?.value ?? ""
        photoURL = person.photos?.first { $0.metadata?.primary == true }?.url ?? person.photos?.first?.url

        if let date = person.birthdays?.first?.date, (date.year ?? date.month ?? date.day) != nil {
            birthday = DateComponents(year: date.year, month: date.month, day: date.day)
        } else {
            birthday = nil
        }

        emails = (person.emailAddresses ?? []).map { LabeledValue(label: $0.type ?? "", value: $0.value ?? "", isPrimary: $0.metadata?.primary == true) }
        phones = (person.phoneNumbers ?? []).map { LabeledValue(label: $0.type ?? "", value: $0.value ?? "", isPrimary: $0.metadata?.primary == true) }
        urls = (person.urls ?? []).map { LabeledValue(label: $0.type ?? "", value: $0.value ?? "", isPrimary: $0.metadata?.primary == true) }
        relations = (person.relations ?? []).map { LabeledValue(label: $0.type ?? "", value: $0.person ?? "", isPrimary: $0.metadata?.primary == true) }
        userDefinedFields = (person.userDefined ?? []).map { LabeledValue(label: $0.key ?? "", value: $0.value ?? "", isPrimary: false) }

        addresses = (person.addresses ?? []).map {
            PostalAddress(label: $0.type ?? "", street: $0.streetAddress ?? "", city: $0.city ?? "", region: $0.region ?? "", postalCode: $0.postalCode ?? "", country: $0.country ?? "", formattedValue: $0.formattedValue ?? "")
        }
        organizations = (person.organizations ?? []).map {
            Organization(name: $0.name ?? "", title: $0.title ?? "", department: $0.department ?? "", isCurrent: $0.current ?? false)
        }

        let membershipResourceNames = (person.memberships ?? []).map(\.contactGroupMembership.contactGroupResourceName)
        memberships = membershipResourceNames.compactMap { groupsByResourceName[$0] }
    }

    /// Builds the outbound DTO from current local state, for create/update pushes.
    public var asPersonDTO: PersonDTO {
        PersonDTO(
            resourceName: resourceName,
            etag: etag,
            names: [NameDTO(metadata: FieldMetadataDTO(primary: true), givenName: givenName, familyName: familyName, middleName: middleName, phoneticGivenName: phoneticGivenName, phoneticFamilyName: phoneticFamilyName)],
            nicknames: nickname.isEmpty ? nil : [NicknameDTO(value: nickname)],
            emailAddresses: emails.isEmpty ? nil : emails.map { LabeledStringDTO(metadata: FieldMetadataDTO(primary: $0.isPrimary), value: $0.value, type: $0.label) },
            phoneNumbers: phones.isEmpty ? nil : phones.map { LabeledStringDTO(metadata: FieldMetadataDTO(primary: $0.isPrimary), value: $0.value, type: $0.label) },
            addresses: addresses.isEmpty ? nil : addresses.map { AddressDTO(metadata: nil, type: $0.label, streetAddress: $0.street, city: $0.city, region: $0.region, postalCode: $0.postalCode, country: $0.country, formattedValue: $0.formattedValue) },
            organizations: organizations.isEmpty ? nil : organizations.map { OrganizationDTO(metadata: nil, name: $0.name, title: $0.title, department: $0.department, current: $0.isCurrent) },
            urls: urls.isEmpty ? nil : urls.map { LabeledStringDTO(metadata: FieldMetadataDTO(primary: $0.isPrimary), value: $0.value, type: $0.label) },
            relations: relations.isEmpty ? nil : relations.map { LabeledStringDTO(type: $0.label, person: $0.value) },
            userDefined: userDefinedFields.isEmpty ? nil : userDefinedFields.map { UserDefinedFieldDTO(key: $0.label, value: $0.value) },
            birthdays: birthday.map { [BirthdayDTO(date: PartialDateDTO(year: $0.year, month: $0.month, day: $0.day))] },
            biographies: notes.isEmpty ? nil : [BiographyDTO(value: notes)]
        )
    }

    /// The top-level People API field-group names that differ between two DTOs, as a comma list
    /// suitable for `updatePersonFields`. Field group names match `PeopleAPIClient.personFields`.
    public static func fieldMask(changedFrom original: PersonDTO, to updated: PersonDTO) -> String {
        var changed: [String] = []
        if original.names != updated.names { changed.append("names") }
        if original.nicknames != updated.nicknames { changed.append("nicknames") }
        if original.emailAddresses != updated.emailAddresses { changed.append("emailAddresses") }
        if original.phoneNumbers != updated.phoneNumbers { changed.append("phoneNumbers") }
        if original.addresses != updated.addresses { changed.append("addresses") }
        if original.organizations != updated.organizations { changed.append("organizations") }
        if original.urls != updated.urls { changed.append("urls") }
        if original.relations != updated.relations { changed.append("relations") }
        if original.userDefined != updated.userDefined { changed.append("userDefined") }
        if original.birthdays != updated.birthdays { changed.append("birthdays") }
        if original.biographies != updated.biographies { changed.append("biographies") }
        return changed.joined(separator: ",")
    }
}
