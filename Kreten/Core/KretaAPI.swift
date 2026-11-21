// KRÉTA routes are derived from Firka and KRETEN. See docs/API.md and docs/UPSTREAM.md.
import Foundation

/// Stateless HTTP transport. Never follows redirects and caps response sizes.
final class KretaAPI: Sendable {
    static let maxJSONBytes = 16 * 1024 * 1024

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.httpAdditionalHeaders = ["User-Agent": OAuth.userAgent]
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    func schoolURL(_ institution: String, _ path: String) -> String { "https://\(institution).e-kreta.hu\(path)" }
    func adminURL(_ path: String) -> String { "https://eugyintezes.e-kreta.hu\(path)" }

    func token(_ form: [(String, String)]) async throws -> JSON {
        var request = URLRequest(url: URL(string: "\(OAuth.idp)/connect/token")!)
        request.httpMethod = "POST"
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(form)
        let (data, response) = try await send(request)
        if [400, 401].contains(response.statusCode) { throw KretaError.authentication }
        try Self.check(response)
        return try Self.decode(data)
    }

    func get(_ url: String, token: String) async throws -> JSON {
        guard let u = URL(string: url) else { throw KretaError.response }
        var request = URLRequest(url: u)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // KRÉTA's mailbox rejects the diary's mobile identification headers.
        if u.path.hasPrefix("/api/v1/kommunikacio/") {
            request.setValue("KRETENDesktop/0.1", forHTTPHeaderField: "User-Agent")
            request.setValue("hu-HU", forHTTPHeaderField: "X-Uzenet-Lokalizacio")
        } else {
            request.setValue(OAuth.apiKey, forHTTPHeaderField: "apiKey")
        }
        let (data, response) = try await send(request)
        try Self.check(response)
        return try Self.decode(data)
    }

    func change(_ method: String, _ url: String, token: String, body: [String: Any]?, form: Bool) async throws {
        guard let u = URL(string: url) else { throw KretaError.response }
        var request = URLRequest(url: u)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(OAuth.apiKey, forHTTPHeaderField: "apiKey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            if form {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = Self.formBody(body.map { ($0.key, "\($0.value)") })
            } else {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
        }
        let (_, response) = try await send(request)
        try Self.check(response)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw KretaError.response }
            guard data.count <= Self.maxJSONBytes else { throw KretaError.response }
            return (data, http)
        } catch let error as KretaError {
            throw error
        } catch {
            throw KretaError.network
        }
    }

    static func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw KretaError.authentication
        default: throw KretaError.http(response.statusCode)
        }
    }

    static func decode(_ data: Data) throws -> JSON {
        do { return try JSON.parse(data) } catch { throw KretaError.response }
    }

    static func formBody(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(pairs.map { k, v in
            "\(k.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").utf8)
    }

    static func validID(_ value: String) throws -> String {
        let ok = value.utf8.allSatisfy { c in
            (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 45 || c == 95
        }
        guard !value.isEmpty, value.count <= 160, ok else { throw KretaError.invalid("azonosító") }
        return value
    }
}

/// Redirects are never followed: a redirect from an API route is an error.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
