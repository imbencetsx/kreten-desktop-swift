// OAuth flow and constants adapted from Firka, QwIT Development, CC BY-NC-SA 4.0.
import CryptoKit
import Foundation

enum OAuth {
    static let clientID = "kreta-ellenorzo-student-mobile-android"
    static let redirectURI = "https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect"
    static let scopes = "openid email offline_access kreta-ellenorzo-webapi.public kreta-eugyintezes-webapi.public kreta-fileservice-webapi.public kreta-mobile-global-webapi.public kreta-dkt-webapi.public kreta-ier-webapi.public"
    static let userAgent = "hu.ekreta.student/5.15.0/KRETENDesktop/13/33"
    static let apiKey = "21ff6c25-d1da-4a68-a811-c881a6057463"
    static let idp = "https://idp.e-kreta.hu"

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }

    /// Institution codes become a subdomain, so they must never escape `*.e-kreta.hu`.
    static func validateInstitution(_ value: String) throws -> String {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = v.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 }
        guard !v.isEmpty, v.utf8.count <= 63, allowed, v.first != "-", v.last != "-" else {
            throw KretaError.institution
        }
        return v
    }

    /// Unverified JWT payload; the token came straight from the IdP over TLS.
    static func claims(_ token: String) throws -> JSON {
        let parts = token.split(separator: ".")
        guard parts.count == 3, let data = Data(base64URL: String(parts[1])) else { throw KretaError.response }
        return try JSON.parse(data)
    }
}

struct PendingLogin: Sendable {
    let id = OAuth.randomToken()
    let state = OAuth.randomToken()
    let nonce = OAuth.randomToken()
    let verifier = OAuth.randomToken()
    let createdAt = Date()
    let url: URL

    init() throws {
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var authorize = URLComponents(string: "\(OAuth.idp)/connect/authorize/callback")!
        authorize.queryItems = [
            .init(name: "redirect_uri", value: OAuth.redirectURI),
            .init(name: "client_id", value: OAuth.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "prompt", value: "login"),
            .init(name: "state", value: state),
            .init(name: "nonce", value: nonce),
            .init(name: "scope", value: OAuth.scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "suppressed_prompt", value: "login"),
        ]
        let returnURL = "\(authorize.path)?\(authorize.percentEncodedQuery ?? "")"
        var login = URLComponents(string: "\(OAuth.idp)/Account/Login")!
        login.queryItems = [.init(name: "ReturnUrl", value: returnURL)]
        guard let url = login.url else { throw KretaError.login }
        self.url = url
    }

    static func isRedirect(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "mobil.e-kreta.hu" && url.path == "/ellenorzo-student/prod/oauthredirect"
    }

    /// Extracts the authorization code after verifying origin, state and freshness.
    func code(from redirect: URL) throws -> String {
        guard Date().timeIntervalSince(createdAt) <= 15 * 60,
              PendingLogin.isRedirect(redirect),
              redirect.port == nil || redirect.port == 443,
              redirect.user == nil, redirect.password == nil, redirect.fragment == nil,
              let items = URLComponents(url: redirect, resolvingAgainstBaseURL: false)?.queryItems
        else { throw KretaError.login }
        let states = items.filter { $0.name == "state" }
        let codes = items.filter { $0.name == "code" }
        guard states.count == 1, states[0].value == state,
              codes.count == 1, let code = codes[0].value, !code.isEmpty,
              !items.contains(where: { $0.name == "error" })
        else { throw KretaError.login }
        return code
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL: String) {
        var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        self.init(base64Encoded: s)
    }

    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
