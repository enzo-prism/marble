import Foundation
import AuthenticationServices

// MARK: - Configuration

/// Credentials and endpoints for Strava's official OAuth 2.0 API.
///
/// Resolved from the app's Info.plist (`StravaClientID`, `StravaClientSecret`,
/// `StravaRedirectURI`) so the keys stay out of source and Strava stays hidden until a
/// developer wires up their own Strava API application. The redirect URI's scheme is
/// claimed transiently by `ASWebAuthenticationSession`, so it needs no `CFBundleURLTypes`
/// registration — but its host must match the "Authorization Callback Domain" configured in
/// the Strava API app.
struct StravaConfiguration: Sendable {
    var clientID: String
    var clientSecret: String
    var redirectURI: String
    var scope: String

    var isConfigured: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty && !redirectURI.isEmpty
    }

    static let placeholder = StravaConfiguration(clientID: "", clientSecret: "", redirectURI: "", scope: "activity:read")

    static var resolved: StravaConfiguration {
        func value(_ key: String) -> String {
            (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let scope = value("StravaScope")
        return StravaConfiguration(
            clientID: value("StravaClientID"),
            clientSecret: value("StravaClientSecret"),
            redirectURI: value("StravaRedirectURI"),
            // `read_all` is needed to see activities the athlete marked "Only Me"; the user
            // still explicitly grants it on Strava's consent screen.
            scope: scope.isEmpty ? "activity:read_all" : scope
        )
    }

    var authorizeURL: URL? {
        guard isConfigured else { return nil }
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: scope)
        ]
        return components?.url
    }
}

// MARK: - Errors

enum StravaError: LocalizedError {
    case notConfigured
    case cancelled
    case accessDenied
    case missingToken
    case unauthorized
    case invalidResponse
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Strava isn’t available in this build."
        case .cancelled:
            return "Strava sign-in was cancelled."
        case .accessDenied:
            return "Strava access wasn’t granted."
        case .missingToken:
            return "Connect your Strava account first."
        case .unauthorized:
            return "Strava access expired. Reconnect your account."
        case .invalidResponse:
            return "Strava returned unreadable data."
        case .requestFailed(let code, let body):
            let detail = body.isEmpty ? "" : " \(body.prefix(140))"
            return "Strava request failed (\(code)).\(detail)"
        }
    }
}

// MARK: - Session

struct StravaSession: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    func hasValidAccessToken(now: Date, margin: TimeInterval = 120) -> Bool {
        expiresAt.timeIntervalSince(now) > margin
    }
}

// MARK: - Client

@MainActor
final class StravaClient {
    let configuration: StravaConfiguration
    private let tokenStore: KeychainTokenStore
    private let session: URLSession
    private let presentationContext = WebAuthPresentationContext()
    private var activeSession: ASWebAuthenticationSession?

    init(
        configuration: StravaConfiguration,
        tokenStore: KeychainTokenStore = KeychainTokenStore(service: "marble.fit.import", account: "strava"),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.session = session
    }

    var hasToken: Bool { storedSession() != nil }

    func disconnect() {
        tokenStore.clear()
    }

    // MARK: Authorization

    func authorize() async throws {
        guard configuration.isConfigured, let url = configuration.authorizeURL else {
            throw StravaError.notConfigured
        }
        let scheme = URL(string: configuration.redirectURI)?.scheme

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
                self?.activeSession = nil
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: StravaError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callback else {
                    continuation.resume(throwing: StravaError.cancelled)
                    return
                }
                continuation.resume(returning: callback)
            }
            authSession.presentationContextProvider = presentationContext
            authSession.prefersEphemeralWebBrowserSession = false
            activeSession = authSession
            authSession.start()
        }

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.first(where: { $0.name == "error" })?.value != nil {
            throw StravaError.accessDenied
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw StravaError.accessDenied
        }
        try await exchange(code: code)
    }

    // MARK: Token lifecycle

    private func exchange(code: String) async throws {
        let token = try await postToken([
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ])
        tokenStore.setSession(session(from: token))
    }

    private func validAccessToken() async throws -> String {
        guard let current = storedSession() else { throw StravaError.missingToken }
        if current.hasValidAccessToken(now: Date()) {
            return current.accessToken
        }
        let token = try await postToken([
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": current.refreshToken
        ])
        let refreshed = session(from: token)
        tokenStore.setSession(refreshed)
        return refreshed.accessToken
    }

    private func postToken(_ form: [String: String]) async throws -> StravaTokenResponse {
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\(Self.percentEncoded($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response, data: data)
        guard let decoded = try? JSONDecoder().decode(StravaTokenResponse.self, from: data) else {
            throw StravaError.invalidResponse
        }
        return decoded
    }

    private func session(from token: StravaTokenResponse) -> StravaSession {
        StravaSession(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(token.expiresAt))
        )
    }

    // MARK: Activities

    func fetchActivities(start: Date?, end: Date?) async throws -> [StravaActivity] {
        let token = try await validAccessToken()

        let perPage = 30
        let maxPages = 5
        var page = 1
        var collected: [StravaActivity] = []

        while page <= maxPages {
            var components = URLComponents(string: "https://www.strava.com/api/v3/athlete/activities")
            var query: [URLQueryItem] = [
                URLQueryItem(name: "per_page", value: String(perPage)),
                URLQueryItem(name: "page", value: String(page))
            ]
            if let start { query.append(URLQueryItem(name: "after", value: String(Int(start.timeIntervalSince1970)))) }
            if let end { query.append(URLQueryItem(name: "before", value: String(Int(end.timeIntervalSince1970)))) }
            components?.queryItems = query
            guard let url = components?.url else { throw StravaError.invalidResponse }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                tokenStore.clear()
                throw StravaError.unauthorized
            }
            try Self.validate(response, data: data)
            guard let pageActivities = try? JSONDecoder().decode([StravaActivity].self, from: data) else {
                throw StravaError.invalidResponse
            }
            collected.append(contentsOf: pageActivities)
            if pageActivities.count < perPage { break }
            page += 1
        }
        return collected
    }

    // MARK: Helpers

    private func storedSession() -> StravaSession? {
        tokenStore.session(StravaSession.self)
    }

    private static func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw StravaError.invalidResponse }
        if http.statusCode == 401 { throw StravaError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw StravaError.requestFailed(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }
}

// MARK: - Wire models

struct StravaTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

struct StravaActivity: Decodable {
    let id: Int64?
    let name: String?
    let distance: Double?           // meters
    let movingTime: Int?            // seconds
    let elapsedTime: Int?           // seconds
    let type: String?
    let sportType: String?
    let startDate: String?          // ISO8601 UTC
    let averageHeartrate: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, distance, type
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case sportType = "sport_type"
        case startDate = "start_date"
        case averageHeartrate = "average_heartrate"
    }
}
