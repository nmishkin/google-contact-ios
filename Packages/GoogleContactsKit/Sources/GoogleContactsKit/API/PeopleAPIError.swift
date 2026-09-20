import Foundation

public struct GoogleAPIErrorDetailDTO: Codable, Equatable, Sendable {
    public var type: String?
    public var reason: String?

    enum CodingKeys: String, CodingKey {
        case type = "@type"
        case reason
    }

    public init(type: String? = nil, reason: String? = nil) {
        self.type = type
        self.reason = reason
    }
}

public struct GoogleAPIErrorBodyDTO: Codable, Equatable, Sendable {
    public var code: Int
    public var message: String
    public var status: String
    public var details: [GoogleAPIErrorDetailDTO]?

    public init(code: Int, message: String, status: String, details: [GoogleAPIErrorDetailDTO]? = nil) {
        self.code = code
        self.message = message
        self.status = status
        self.details = details
    }

    public var isExpiredSyncToken: Bool {
        details?.contains { $0.reason == "EXPIRED_SYNC_TOKEN" } == true
    }
}

public struct GoogleAPIErrorEnvelope: Codable, Equatable, Sendable {
    public var error: GoogleAPIErrorBodyDTO

    public init(error: GoogleAPIErrorBodyDTO) {
        self.error = error
    }
}

public enum PeopleAPIError: Error, Equatable, Sendable {
    case expiredSyncToken
    case etagMismatch(current: PersonDTO)
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int, message: String)
    case decoding(String)
    case network(String)
}
