import Foundation
import Synchronization

extension TimeZone {
    static let budapest = TimeZone(identifier: "Europe/Budapest")!
}

extension Calendar {
    /// Gregorian calendar pinned to Budapest: school days don't depend on the Mac's time zone.
    static let budapest: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .budapest
        c.firstWeekday = 2
        c.locale = Locale(identifier: "hu_HU")
        return c
    }()
}

/// School days are handled as "YYYY-MM-DD" strings (lexicographically ordered), like the API.
enum Day {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .budapest
        f.timeZone = .budapest
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let localTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .budapest
        f.timeZone = .budapest
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static var today: String { string(Date()) }
    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ day: String) -> Date? { day.count == 10 ? formatter.date(from: day) : nil }

    static func add(_ day: String, _ days: Int) -> String {
        guard let d = date(day), let r = Calendar.budapest.date(byAdding: .day, value: days, to: d) else { return day }
        return string(r)
    }

    /// 1 = Monday … 7 = Sunday.
    static func weekday(_ day: String) -> Int {
        guard let d = date(day) else { return 1 }
        return (Calendar.budapest.component(.weekday, from: d) + 5) % 7 + 1
    }

    static func isWeekend(_ day: String) -> Bool { weekday(day) >= 6 }
    static func monday(of day: String) -> String { add(day, -(weekday(day) - 1)) }
    static func schoolYear(of day: String) -> Int {
        let y = Int(day.prefix(4)) ?? 2000, m = Int(day.dropFirst(5).prefix(2)) ?? 1
        return m >= 9 ? y : y - 1
    }
    static func days(from a: String, to b: String) -> Int {
        guard let x = date(a), let y = date(b) else { return 0 }
        return Calendar.budapest.dateComponents([.day], from: x, to: y).day ?? 0
    }

    /// Normalizes an API date/timestamp to its Budapest calendar day.
    static func of(_ value: JSON) -> String { of(value.text) }
    static func of(_ s: String) -> String {
        if s.utf8.count == 10, isDay(s.utf8) { return s }
        if isLocalTimestamp(s) { return String(s.prefix(10)) }
        return timestamp(s).map(string) ?? ""
    }

    /// Unzoned school timestamps are Budapest wall-clock; zoned ones are absolute.
    static func timestamp(_ s: String) -> Date? {
        if isLocalTimestamp(s) {
            var t = String(s.prefix(19))
            if t.count == 16 { t += ":00" }
            return localTimestamp.date(from: t)
        }
        return isoFractional.date(from: s) ?? iso.date(from: s)
    }

    // ISO8601DateFormatter is thread-safe; building one costs far more than parsing.
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// `YYYY-MM-DD` (only the first 10 bytes are checked).
    private static func isDay(_ u: String.UTF8View) -> Bool {
        var i = 0
        for c in u.prefix(10) {
            let ok = (i == 4 || i == 7) ? c == UInt8(ascii: "-") : (c >= 48 && c <= 57)
            if !ok { return false }
            i += 1
        }
        return i == 10
    }

    /// `YYYY-MM-DDTHH:MM[:SS[.fff]]` with no zone: Budapest wall-clock time.
    /// Hand-rolled instead of a regex: this runs for every lesson on every sync.
    static func isLocalTimestamp(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard u.count >= 16, isDay(s.utf8), u[10] == UInt8(ascii: "T") else { return false }
        func digits(_ r: Range<Int>) -> Bool { r.upperBound <= u.count && u[r].allSatisfy { $0 >= 48 && $0 <= 57 } }
        guard digits(11..<13), u[13] == UInt8(ascii: ":"), digits(14..<16) else { return false }
        if u.count == 16 { return true }
        guard u[16] == UInt8(ascii: ":"), digits(17..<19) else { return false }
        if u.count == 19 { return true }
        return u[19] == UInt8(ascii: ".") && u.count > 20 && digits(20..<u.count)
    }
}

enum Format {
    static let hu = Locale(identifier: "hu_HU")

    /// Formatted day labels repeat constantly across rows and re-renders; ICU
    /// formatting is slow on older Macs, so each label is built once.
    private static let cache = Mutex<[String: String]>([:])
    private static func cached(_ key: String, _ make: () -> String) -> String {
        if let hit = cache.withLock({ $0[key] }) { return hit }
        let value = make()
        cache.withLock { if $0.count > 2000 { $0.removeAll() }; $0[key] = value }
        return value
    }

    /// "nov. 14." or "2026. nov. 14."
    static func day(_ day: String, year: Bool = false) -> String {
        guard day.utf8.count == 10 else { return day.isEmpty ? "Nincs megadva" : day }
        return cached(year ? "y" + day : "d" + day) {
            guard let d = Day.date(day) else { return day }
            var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: hu, calendar: .budapest, timeZone: .budapest)
                .month(.abbreviated).day()
            if year { style = style.year() }
            return d.formatted(style)
        }
    }

    static func weekday(_ day: String) -> String {
        guard day.utf8.count == 10 else { return "" }
        return cached("w" + day) {
            guard let d = Day.date(day) else { return "" }
            return d.formatted(Date.FormatStyle(locale: hu, calendar: .budapest, timeZone: .budapest).weekday(.wide)).capitalized(with: hu)
        }
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: hu, calendar: .budapest, timeZone: .budapest).year().month(.wide).day().weekday(.wide))
    }

    /// "08:00" from a school timestamp.
    static func time(_ s: String) -> String {
        // Only unzoned timestamps are already Budapest wall-clock time. Zoned ones
        // ("…Z", "+01:00") must be converted, or every lesson shows an hour early.
        if Day.isLocalTimestamp(s) {
            return String(s.dropFirst(11).prefix(5))
        }
        guard let d = Day.timestamp(s) else { return "—" }
        return time(d)
    }

    static func time(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(locale: hu, calendar: .budapest, timeZone: .budapest).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func decimal(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v.formatted(.number.precision(.fractionLength(2)).locale(hu))
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(hu))
    }
}
