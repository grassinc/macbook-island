import Foundation

/// Microsoft Graph sign-in using the OAuth 2.0 device authorization grant.
///
/// Device code is the right flow here: a desktop app has no safe redirect URI
/// and cannot keep a client secret. The user is shown a short code, types it at
/// microsoft.com/devicelogin, and we poll for the token. The Azure app
/// registration is therefore a PUBLIC client with no secret to leak.
///
/// Scope is `Mail.ReadBasic`, which returns everything except message bodies —
/// the brief asked to prefer metadata-only access where it is sufficient, and
/// for sender plus subject it is. Archiving would additionally need
/// `Mail.ReadWrite`, which is a separate consent worth asking for separately.
actor GraphAuth {

    struct Configuration: Codable, Sendable {
        var clientID: String
        /// "common" works for both work/school and personal accounts.
        var tenant: String = "common"
        var scopes: [String] = ["offline_access", "Mail.ReadBasic"]
    }

    struct DeviceCode: Sendable {
        let userCode: String
        let verificationURL: URL
        let deviceCode: String
        let interval: TimeInterval
        let expiresAt: Date
    }

    enum AuthError: LocalizedError {
        case notConfigured
        case http(Int, String)
        case declined(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .notConfigured: "No Azure client ID configured yet"
            case .http(let code, let body): "Microsoft returned \(code): \(body)"
            case .declined(let reason): "Sign-in did not complete: \(reason)"
            case .timedOut: "The sign-in code expired before it was entered"
            }
        }
    }

    private let configuration: Configuration
    private var accessToken: String?
    private var accessTokenExpiry: Date?

    private static let refreshTokenAccount = "refresh-token"

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    private var base: String { "https://login.microsoftonline.com/\(configuration.tenant)/oauth2/v2.0" }
    private var scopeString: String { configuration.scopes.joined(separator: " ") }

    var isSignedIn: Bool { Keychain.get(Self.refreshTokenAccount) != nil }

    func signOut() {
        Keychain.delete(Self.refreshTokenAccount)
        accessToken = nil
        accessTokenExpiry = nil
    }

    // MARK: - Device code flow

    func beginDeviceCodeFlow() async throws -> DeviceCode {
        guard !configuration.clientID.isEmpty else { throw AuthError.notConfigured }

        let body = form(["client_id": configuration.clientID, "scope": scopeString])
        let json = try await post(url: URL(string: "\(base)/devicecode")!, body: body)

        guard let userCode = json["user_code"] as? String,
              let deviceCode = json["device_code"] as? String,
              let verification = (json["verification_uri"] as? String)
                    ?? (json["verification_url"] as? String),
              let url = URL(string: verification) else {
            throw AuthError.declined("Malformed device code response")
        }
        let interval = (json["interval"] as? Double) ?? 5
        let expiresIn = (json["expires_in"] as? Double) ?? 900

        return DeviceCode(userCode: userCode, verificationURL: url, deviceCode: deviceCode,
                          interval: interval, expiresAt: Date().addingTimeInterval(expiresIn))
    }

    /// Polls until the user completes sign-in, honouring the interval Microsoft
    /// asks for. `authorization_pending` is the normal case, not an error.
    func pollForToken(_ code: DeviceCode) async throws {
        var interval = code.interval

        while Date() < code.expiresAt {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

            let body = form([
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": configuration.clientID,
                "device_code": code.deviceCode,
            ])
            let json = try? await post(url: URL(string: "\(base)/token")!, body: body)

            if let json, let token = json["access_token"] as? String {
                store(accessToken: token, json: json)
                return
            }
            switch (json?["error"] as? String) ?? "authorization_pending" {
            case "authorization_pending": continue
            case "slow_down":            interval += 5
            case "expired_token":        throw AuthError.timedOut
            case let other:              throw AuthError.declined(other)
            }
        }
        throw AuthError.timedOut
    }

    // MARK: - Tokens

    /// A valid access token, refreshing when needed.
    func validAccessToken() async throws -> String {
        if let accessToken, let expiry = accessTokenExpiry, expiry > Date().addingTimeInterval(60) {
            return accessToken
        }
        guard let refresh = Keychain.get(Self.refreshTokenAccount) else {
            throw AuthError.declined("Not signed in")
        }
        let body = form([
            "grant_type": "refresh_token",
            "client_id": configuration.clientID,
            "refresh_token": refresh,
            "scope": scopeString,
        ])
        let json = try await post(url: URL(string: "\(base)/token")!, body: body)
        guard let token = json["access_token"] as? String else {
            throw AuthError.declined("Refresh failed")
        }
        store(accessToken: token, json: json)
        return token
    }

    private func store(accessToken token: String, json: [String: Any]) {
        accessToken = token
        let lifetime = (json["expires_in"] as? Double) ?? 3600
        accessTokenExpiry = Date().addingTimeInterval(lifetime)
        // Microsoft rotates refresh tokens; always keep the newest.
        if let refresh = json["refresh_token"] as? String {
            Keychain.set(refresh, for: Self.refreshTokenAccount)
        }
    }

    // MARK: - HTTP

    private func form(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func post(url: URL, body: Data) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // The token endpoint returns 400 for authorization_pending, which is
            // expected while the user is still typing the code.
            if json["error"] != nil { return json }
            throw AuthError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return json
    }
}
