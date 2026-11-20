import Foundation

/// School-calendar progress (week, next break, school year). Breaks come from
/// KRÉTA's `TanevRendjeElemek`; missing ones use the usual Hungarian schedule.
struct SchoolBreak: Hashable {
    var name: String
    var start: String // first day without school
    var end: String   // last day without school
    var estimated: Bool
}

struct SchoolCalendar {
    var firstDay: String
    var lastDay: String
    var firstEstimated: Bool
    var lastEstimated: Bool
    var breaks: [SchoolBreak]
    var offDays: Set<String>

    static func easter(_ year: Int) -> String {
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = (h + l - 7 * m + 114) % 31 + 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func estimated(_ year: Int) -> (first: String, last: String, breaks: [SchoolBreak]) {
        var first = "\(year)-09-01"
        while Day.isWeekend(first) { first = Day.add(first, 1) }
        var last = "\(year + 1)-06-01" // third Friday of June
        while Day.weekday(last) != 5 { last = Day.add(last, 1) }
        last = Day.add(last, 14)
        let oct29 = "\(year)-10-29"
        let autumnMonday = Day.monday(of: oct29)
        var winterStart = "\(year)-12-17"
        while Day.weekday(winterStart) != 6 { winterStart = Day.add(winterStart, 1) }
        var winterEnd = "\(year + 1)-01-01"
        while Day.weekday(winterEnd) != 7 { winterEnd = Day.add(winterEnd, 1) }
        let easter = easter(year + 1)
        return (first, last, [
            SchoolBreak(name: "Őszi szünet", start: Day.add(autumnMonday, -2), end: Day.add(autumnMonday, 6), estimated: true),
            SchoolBreak(name: "Téli szünet", start: winterStart, end: winterEnd, estimated: true),
            SchoolBreak(name: "Tavaszi szünet", start: Day.add(easter, -3), end: Day.add(easter, 2), estimated: true),
        ])
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func season(_ start: String, _ end: String, _ label: String) -> String {
        if matches(label, "őszi|oszi") { return "Őszi szünet" }
        if matches(label, "téli|teli") { return "Téli szünet" }
        if matches(label, "tavaszi") { return "Tavaszi szünet" }
        let middle = Day.add(start, Day.days(from: start, to: end) / 2)
        let month = Int(middle.dropFirst(5).prefix(2)) ?? 0
        switch month {
        case 10, 11: return "Őszi szünet"
        case 12, 1: return "Téli szünet"
        case 3...5: return "Tavaszi szünet"
        default: return "Tanítási szünet"
        }
    }

    init(_ data: JSON, today: String = Day.today) {
        let year = Day.schoolYear(of: today)
        let items = data.rows.map { (day: Day.of($0["Datum"]), label: "\($0["Naptipus"]["Nev"].text) \($0["Naptipus"]["Leiras"].text)") }
            .filter { !$0.day.isEmpty && $0.day >= "\(year)-08-01" && $0.day <= "\(year + 1)-07-31" }
        let estimate = Self.estimated(year)
        let first = items.filter { Self.matches($0.label, "első tanítási nap|elsotanitasinap") }.map(\.day).min()
        let last = items.filter { Self.matches($0.label, "utolsó tanítási nap|utolsotanitasinap") }.map(\.day).max()
        firstDay = first ?? estimate.first
        lastDay = last ?? estimate.last
        firstEstimated = first == nil
        lastEstimated = last == nil

        var labels: [String: String] = [:]
        for i in items where Self.matches(i.label, "szünet|szunet|ünnep|unnep|munkaszüneti|munkaszuneti|tanítás nélküli|tanitasnelkuli")
            && !Self.matches(i.label, "nyári|nyari") && !Day.isWeekend(i.day) {
            labels[i.day, default: ""] += " \(i.label)"
        }
        offDays = Set(labels.keys)

        // Runs of off weekdays (bridging weekends) inside the teaching period.
        var found: [SchoolBreak] = []
        var run: [String] = []
        let (fd, ld) = (firstDay, lastDay)
        func flush() {
            if run.count >= 3, run.contains(where: { Self.matches(labels[$0] ?? "", "szünet|szunet") }) {
                var s = run[0], e = run[run.count - 1]
                while Day.isWeekend(Day.add(s, -1)) { s = Day.add(s, -1) }
                while Day.isWeekend(Day.add(e, 1)) { e = Day.add(e, 1) }
                found.append(SchoolBreak(name: Self.season(s, e, run.map { labels[$0] ?? "" }.joined(separator: " ")), start: s, end: e, estimated: false))
            }
            run = []
        }
        for d in offDays.filter({ $0 > fd && $0 < ld }).sorted() {
            if let previous = run.last {
                var gap = Day.add(previous, 1)
                while gap < d && Day.isWeekend(gap) { gap = Day.add(gap, 1) }
                if gap != d { flush() }
            }
            run.append(d)
        }
        flush()
        var breaks = found
        for guess in estimate.breaks where !found.contains(where: { $0.name == guess.name }) && guess.start > fd && guess.end < ld {
            breaks.append(guess)
        }
        self.breaks = breaks.sorted { $0.start < $1.start }
    }

    func teachingDays(from: String, to: String) -> Int {
        var count = 0
        var d = from
        while d < to {
            if d >= firstDay, d <= lastDay, !Day.isWeekend(d), !offDays.contains(d), !breaks.contains(where: { d >= $0.start && d <= $0.end }) {
                count += 1
            }
            d = Day.add(d, 1)
        }
        return count
    }
}

struct ProgressSpan {
    var fraction: Double
    var remaining: TimeInterval
    var remainingDays: Int
    var schoolDaysLeft: Int
}

enum SchoolProgress {
    private static func start(_ day: String) -> Date { Day.date(day) ?? Date() }

    private static func span(_ from: Date, _ to: Date, now: Date, calendar: SchoolCalendar?) -> ProgressSpan {
        let today = Day.string(now), target = Day.string(to)
        return ProgressSpan(
            fraction: to > from ? min(1, max(0, now.timeIntervalSince(from) / to.timeIntervalSince(from))) : 1,
            remaining: max(0, to.timeIntervalSince(now)),
            remainingDays: max(0, Day.days(from: today, to: target)),
            schoolDaysLeft: calendar?.teachingDays(from: today, to: target) ?? 0)
    }

    /// Monday 00:00 → Saturday 00:00.
    static func week(now: Date) -> (span: ProgressSpan, weekend: Bool) {
        let today = Day.string(now)
        let monday = Day.monday(of: today)
        var s = span(start(monday), start(Day.add(monday, 5)), now: now, calendar: nil)
        let weekend = Day.isWeekend(today)
        s.schoolDaysLeft = weekend ? 0 : 6 - Day.weekday(today)
        if weekend { s.remaining = start(Day.add(monday, 7)).timeIntervalSince(now) }
        return (s, weekend)
    }

    static func nextBreak(_ cal: SchoolCalendar, now: Date) -> (span: ProgressSpan, current: SchoolBreak?, next: SchoolBreak?) {
        let today = Day.string(now)
        let current = cal.breaks.first { today >= $0.start && today <= $0.end }
        let next = cal.breaks.first { $0.start > today }
        if let current {
            return (span(start(current.start), start(Day.add(current.end, 1)), now: now, calendar: nil), current, next)
        }
        guard let next else { return (ProgressSpan(fraction: 0, remaining: 0, remainingDays: 0, schoolDaysLeft: 0), nil, nil) }
        let previous = cal.breaks.last { $0.end < today }
        let since = previous.map { $0.end >= cal.firstDay ? Day.add($0.end, 1) : cal.firstDay } ?? cal.firstDay
        return (span(start(since), start(next.start), now: now, calendar: cal), nil, next)
    }

    enum Phase { case before, during, after }

    static func year(_ cal: SchoolCalendar, now: Date) -> (span: ProgressSpan, phase: Phase) {
        let from = start(cal.firstDay), to = start(Day.add(cal.lastDay, 1))
        var s = span(from, to, now: now, calendar: cal)
        s.remainingDays = max(0, Day.days(from: Day.string(now), to: cal.lastDay))
        return (s, now < from ? .before : now >= to ? .after : .during)
    }
}
