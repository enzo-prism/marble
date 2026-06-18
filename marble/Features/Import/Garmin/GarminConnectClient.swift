import Foundation

struct GarminConnectConfiguration: Sendable {
    var clientID: String
    var clientSecret: String
    var redirectURI: String
    var apiBaseURL: URL
    var authBaseURL: URL

    var isConfigured: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty && !redirectURI.isEmpty
    }

    static let placeholder = GarminConnectConfiguration(
        clientID: "",
        clientSecret: "",
        redirectURI: "",
        apiBaseURL: URL(string: "https://connectapi.garmin.com")!,
        authBaseURL: URL(string: "https://sso.garmin.com")!
    )
}

enum GarminConnectError: LocalizedError {
    case notConfigured
    case missingToken
    case unauthorized
    case invalidResponse
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Garmin Connect isn’t configured. Add your API credentials to enable sync."
        case .missingToken:
            return "Connect your Garmin account first."
        case .unauthorized:
            return "Garmin access expired. Reconnect your account."
        case .invalidResponse:
            return "Garmin returned unreadable data."
        case .requestFailed(let code, let body):
            return "Garmin request failed (\(code)). \(body)"
        }
    }
}

@MainActor
final class GarminConnectClient {
    let configuration: GarminConnectConfiguration
    private let tokenStore: KeychainTokenStore
    private let session: URLSession

    init(
        configuration: GarminConnectConfiguration,
        tokenStore: KeychainTokenStore = KeychainTokenStore(service: "marble.fit.import", account: "garmin-connect"),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.session = session
    }

    var hasToken: Bool { tokenStore.token() != nil }

    var authorizationURL: URL? {
        guard configuration.isConfigured else { return nil }
        var components = URLComponents(url: configuration.authBaseURL.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: "activity:read")
        ]
        return components?.url
    }

    func completeAuthorization(code: String) async throws {
        guard configuration.isConfigured else { throw GarminConnectError.notConfigured }
        var request = URLRequest(url: configuration.authBaseURL.appendingPathComponent("oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret,
            "redirect_uri": configuration.redirectURI
        ]
        request.httpBody = body
            .map { "\($0.key)=\(percentEncoded($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GarminConnectError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GarminConnectError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let tokenResponse = try JSONDecoder().decode(GarminTokenResponse.self, from: data)
        tokenStore.setToken(tokenResponse.accessToken)
    }

    func fetchActivities(start: Date?, end: Date?) async throws -> [GarminActivity] {
        guard configuration.isConfigured else { throw GarminConnectError.notConfigured }
        guard let token = tokenStore.token() else { throw GarminConnectError.missingToken }

        var components = URLComponents(
            url: configuration.apiBaseURL.appendingPathComponent("activity-service/activity/activities"),
            resolvingAgainstBaseURL: false
        )
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "50")]
        if let start { queryItems.append(URLQueryItem(name: "startDate", value: Self.isoFormatter.string(from: start))) }
        if let end { queryItems.append(URLQueryItem(name: "endDate", value: Self.isoFormatter.string(from: end))) }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw GarminConnectError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GarminConnectError.invalidResponse }
        if http.statusCode == 401 {
            tokenStore.clear()
            throw GarminConnectError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GarminConnectError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let decoded: GarminActivitiesResponse
        do {
            decoded = try JSONDecoder().decode(GarminActivitiesResponse.self, from: data)
        } catch {
            throw GarminConnectError.invalidResponse
        }
        return decoded.activities
    }

    func disconnect() {
        tokenStore.clear()
    }

    private func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct GarminTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct GarminActivitiesResponse: Decodable {
    let activities: [GarminActivity]
}

struct GarminActivity: Decodable {
    let activityId: Int?
    let activityName: String?
    let startTimeGMT: String?
    let duration: Double?
    let distance: Double?
    let averageHR: Double?
    let maxHR: Double?
    let calories: Double?
    let activityType: GarminActivityType?
}

struct GarminActivityType: Decodable {
    let typeKey: String?
}
