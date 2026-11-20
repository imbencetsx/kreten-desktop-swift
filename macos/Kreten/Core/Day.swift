import Foundation

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
        if s.count >= 10, s.range(of: #"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2}(\.\d+)?)?)?$"#, options: .regularExpression) != nil {
            return String(s.prefix(10))
        }
        return timestamp(s).map(string) ?? ""
    }

    /// Unzoned school timestamps are Budapest wall-clock; zoned ones are absolute.
    static func timestamp(_ s: String) -> Date? {
        if s.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?(\.\d+)?$"#, options: .regularExpression) != nil {
            var t = String(s.prefix(19))
            if t.count == 16 { t += ":00" }
            return localTimestamp.date(from: t)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }
}

enum Format {
    static let hu = Locale(identifier: "hu_HU")

    /// "nov. 14." or "2026. nov. 14."
    static func day(_ day: String, year: Bool = false) -> String {
        guard let d = Day.date(day) else { return day.isEmpty ? "Nincs megadva" : day }
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: hu, calendar: .budapest, timeZone: .budapest)
            .month(.abbreviated).day()
        if year { style = style.year() }
        return d.formatted(style)
    }

    static func weekday(_ day: String) -> String {
        guard let d = Day.date(day) else { return "" }
        return d.formatted(Date.FormatStyle(locale: hu, calendar: .budapest, timeZone: .budapest).weekday(.wide)).capitalized(with: hu)
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: hu, calendar: .budapest, timeZone: .budapest).year().month(.wide).day().weekday(.wide))
    }

    /// "08:00" from a school timestamp.
    static func time(_ s: String) -> String {
        // Only unzoned timestamps are already Budapest wall-clock time. Zoned ones
        // ("…Z", "+01:00") must be converted, or every lesson shows an hour early.
        if s.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?$"#, options: .regularExpression) != nil {
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
