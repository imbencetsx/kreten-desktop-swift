import Foundation

/// Loosely-typed KRÉTA payload. The API mixes casing, nesting and number/string
/// representations, so raw responses are cached as-is and normalized on read.
enum JSON: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    static func parse(_ data: Data) throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: data)
    }

    subscript(key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    /// First non-null value among several possible keys.
    subscript(keys: String...) -> JSON {
        guard case .object(let o) = self else { return .null }
        for k in keys { if let v = o[k], !v.isNull { return v } }
        return .null
    }

    var isNull: Bool { if case .null = self { return true }; return false }
    var isObject: Bool { if case .object = self { return true }; return false }
    var array: [JSON]? { if case .array(let a) = self { return a }; return nil }
    var rows: [JSON] { (array ?? []).filter(\.isObject) }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var truthy: Bool {
        switch self {
        case .bool(let b): b
        case .number(let n): n != 0
        case .string(let s): !s.isEmpty
        case .array, .object: true
        case .null: false
        }
    }

    var number: Double? {
        switch self {
        case .number(let n): n
        case .string(let s): Double(s.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    /// Strings verbatim, numbers without a trailing ".0", objects via their name fields.
    var text: String {
        switch self {
        case .string(let s): return s
        case .number(let n):
            return n.rounded() == n && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .object: return self["Leiras", "Nev", "nev", "name"].text
        default: return ""
        }
    }

    /// Name of a nested entity (`{Nev: …}`) or the value itself.
    var name: String {
        if isObject { return self["Nev", "nev", "Leiras"].text }
        return text
    }

    /// KRÉTA content can contain HTML. Strip it to inert plain text.
    var plain: String { JSON.stripHTML(text) }

    static func stripHTML(_ html: String) -> String {
        guard html.contains("<") || html.contains("&") else {
            return html.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var s = html
        for tag in ["<br>", "<br/>", "<br />", "</p>", "</div>", "</li>"] {
            s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stable serialization for change fingerprints (sorted keys).
    var canonicalData: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    /// Item identity used for de-duplication and change tracking.
    var itemID: String? {
        let v = self["Uid", "uid", "azonosito", "Id", "id"]
        return v.isNull ? nil : v.text
    }
}
