import Foundation

// Typed views over cached KRÉTA payloads (port of the web client's data.ts).

struct Grade: Identifiable, Hashable {
    var id: String
    var subject: String
    var value: Int
    var display: String
    var weight: Double
    var date: String
    var topic: String
    var teacher: String
    var type: String
    var kind: String

    var isNumeric: Bool {
        (1...5).contains(value) && kind.range(of: "felev|evveg|félév|évvég", options: [.regularExpression, .caseInsensitive]) == nil
    }

    static func parse(_ data: JSON) -> [Grade] {
        let isCode = { (s: String) in s.range(of: #"^jegy_\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil }
        return data.rows.enumerated().map { i, g in
            let topic = g["Tema"].text
            let type = g["Mod"].isNull ? g["Tipus"].text : g["Mod"].text
            let numeric = g["SzamErtek"].number.map { Int($0) } ?? 0
            let display = g["SzamErtek"].isNull ? g["SzovegesErtekelesRovidNev", "SzovegesErtek"].text : g["SzamErtek"].text
            let subject = g["Tantargy"].name
            return Grade(
                id: g["Uid"].text.isEmpty ? "\(i)" : g["Uid"].text,
                subject: subject.isEmpty ? "Értékelés" : subject,
                value: numeric,
                display: display,
                weight: max(0, g["SulySzazalekErteke"].number ?? 100),
                date: Day.of(g["KeszitesDatuma", "RogzitesDatuma"]),
                topic: isCode(topic) ? "" : topic,
                teacher: g["ErtekeloTanarNeve"].text,
                type: isCode(type) ? "" : type,
                kind: g["Tipus"].isObject ? g["Tipus"]["Nev"].text : g["Jelleg"].text)
        }.sorted { $0.date > $1.date }
    }
}

extension Array where Element == Grade {
    var numeric: [Grade] { filter(\.isNumeric) }

    /// Weighted average of numeric 1–5 marks; nil when nothing counts.
    var average: Double? {
        let valid = numeric.filter { $0.weight > 0 }
        let w = valid.reduce(0) { $0 + $1.weight }
        return w > 0 ? valid.reduce(0) { $0 + Double($1.value) * $1.weight } / w : nil
    }

    var bySubject: [SubjectGroup] {
        Dictionary(grouping: self, by: \.subject)
            .map { SubjectGroup(name: $0.key, grades: $0.value) }
            .sorted { $0.name.compare($1.name, locale: Format.hu) == .orderedAscending }
    }

    var monthlyTrend: [(month: String, value: Double)] {
        Dictionary(grouping: numeric.filter { !$0.date.isEmpty }) { String($0.date.prefix(7)) }
            .compactMap { k, v in v.average.map { (k, $0) } }
            .sorted { $0.month < $1.month }
    }

    /// Running weighted average at the end of each day with grades, oldest first.
    /// One point per day: several grades on one date must not stack on one x value.
    var cumulativeTrend: [(date: Date, value: Double)] {
        var out: [(date: Date, value: Double)] = []
        var sum = 0.0, weight = 0.0
        for g in numeric.filter({ $0.weight > 0 }).sorted(by: { $0.date < $1.date }) {
            guard let d = Day.date(g.date) else { continue }
            sum += Double(g.value) * g.weight
            weight += g.weight
            if out.last?.date == d { out[out.count - 1].value = sum / weight } else { out.append((d, sum / weight)) }
        }
        return out
    }

    func period(_ p: GradePeriod) -> [Grade] {
        filter { g in
            let m = Int(g.date.dropFirst(5).prefix(2)) ?? 0
            return switch p {
            case .all: true
            case .first: m >= 9 || m == 1
            case .second: m >= 2 && m <= 8
            }
        }
    }
}

enum GradePeriod: String, CaseIterable, Identifiable {
    case all, first, second
    var id: Self { self }
    var label: String { switch self { case .all: "Egész tanév"; case .first: "1. félév"; case .second: "2. félév" } }
}

struct SubjectGroup: Identifiable, Hashable {
    var name: String
    var grades: [Grade]
    var id: String { name }
    var average: Double? { grades.average }
}

/// Local estimate of the final mark from configurable thresholds.
func estimatedGrade(_ value: Double?, thresholds: [Double]) -> Int? {
    guard let value, value >= 1, value <= 5 else { return nil }
    let valid = thresholds.count == 4 && zip(thresholds, thresholds.dropFirst()).allSatisfy { $0 < $1 } && thresholds.allSatisfy { (1...5).contains($0) }
    return 1 + (valid ? thresholds : [1.5, 2.5, 3.5, 4.5]).filter { value >= $0 }.count
}

struct Lesson: Identifiable, Hashable {
    var id: String
    var subject: String
    var start: String
    var end: String
    var date: String
    var number: Int
    var room: String
    var teacher: String
    var topic: String
    var state: String
    var substitute: String
    var cancelled: Bool
    var subjectID = ""

    var startDate: Date? { Day.timestamp(start) }
    var endDate: Date? { Day.timestamp(end) }
    var timeRange: String { "\(Format.time(start))–\(Format.time(end))" }
    var displayTeacher: String { substitute.isEmpty ? teacher : substitute }

    static func parse(_ data: JSON) -> [Lesson] {
        data.rows.enumerated().map { i, l in
            let subject = l["Tantargy"].name
            let state = l["Allapot"].isObject ? l["Allapot"]["Nev"].text : l["Allapot"].text
            return Lesson(
                id: l["Uid"].text.isEmpty ? "\(i)" : l["Uid"].text,
                subject: subject.isEmpty ? l["Nev"].text : subject,
                start: l["KezdetIdopont"].text, end: l["VegIdopont"].text,
                date: Day.of(l["Datum", "KezdetIdopont"]),
                number: Int(l["Oraszam"].number ?? 0),
                room: l["TeremNeve"].text, teacher: l["TanarNeve"].text, topic: l["Tema"].text,
                state: l["Allapot"].text,
                substitute: l["HelyettesTanarNeve"].text,
                cancelled: (state + l["Allapot"].text).range(of: "elmarad", options: .caseInsensitive) != nil,
                subjectID: l["Tantargy"]["Uid"].text)
        }.sorted { $0.start < $1.start }
    }
}

/// What's happening right now: a lesson, a break between lessons, or the next lesson.
struct LiveStatus: Equatable {
    enum Kind { case lesson, breakTime, upcoming, empty }
    var kind: Kind = .empty
    var label = "SZABAD IDŐ"
    var title = "Nincs közelgő tanóra."
    var details = "Nincs több közelgő óra a következő napokra."
    var secondary = ""
    var date = ""
    var start: Date?
    var end: Date?

    func progress(at now: Date) -> Double {
        guard let start, let end, end > start else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    static func compute(_ lessons: [Lesson], now: Date) -> LiveStatus {
        let items = lessons.filter { !$0.cancelled }.compactMap { l -> (Lesson, Date, Date)? in
            guard let s = l.startDate, let e = l.endDate, e > s else { return nil }
            return (l, s, e)
        }.sorted { $0.1 < $1.1 }
        let active = items.first { $0.1 <= now && now < $0.2 }
        let upcoming = items.first { $0.1 > now }
        let previous = items.filter { $0.2 <= now }.max { $0.2 < $1.2 }
        var s = LiveStatus()
        if let (l, start, end) = active {
            s = LiveStatus(kind: .lesson, label: "MOST ÓRÁD VAN", title: l.subject.isEmpty ? "Tanóra" : l.subject,
                           details: "\(l.timeRange) · \(l.room.isEmpty ? "Terem nincs megadva" : l.room)",
                           secondary: l.displayTeacher, date: l.date, start: start, end: end)
        } else if let (next, nextStart, _) = upcoming, let (prev, _, prevEnd) = previous, prev.date == next.date {
            s = LiveStatus(kind: .breakTime, label: "KÉT ÓRA KÖZÖTT", title: "Szünet",
                           details: "Következik: \(next.subject) · \(next.timeRange)",
                           secondary: next.room, date: next.date, start: prevEnd, end: nextStart)
        } else if let (l, start, _) = upcoming {
            s = LiveStatus(kind: .upcoming, label: "A KÖVETKEZŐ ÓRÁD", title: l.subject.isEmpty ? "Tanóra" : l.subject,
                           details: "\(l.timeRange) · \(l.room.isEmpty ? "Terem nincs megadva" : l.room)",
                           secondary: l.displayTeacher, date: l.date, start: nil, end: start)
        }
        return s
    }
}

struct Homework: Identifiable, Hashable {
    var id, subject, text, teacher, date, created: String
    var doneInKreta: Bool

    static func parse(_ data: JSON) -> [Homework] {
        data.rows.enumerated().map { i, h in
            let id = h["Uid", "uid", "Id", "id"].text
            let subject = h["Tantargy"].name
            return Homework(
                id: id.isEmpty ? "\(i)" : id,
                subject: subject.isEmpty ? (h["TantargyNeve"].text.isEmpty ? "Házi feladat" : h["TantargyNeve"].text) : subject,
                text: h["Szoveg", "Tartalom", "Leiras"].plain,
                teacher: h["RogzitoTanarNeve", "TanarNeve"].text,
                date: Day.of(h["HataridoDatuma", "Datum"]),
                created: Day.of(h["FeladasDatuma", "RogzitesDatuma"]),
                doneInKreta: h["IsMegoldva", "IsHaziFeladatMegoldva"].truthy)
        }.sorted { $0.date < $1.date }
    }
}

struct AnnouncedTest: Identifiable, Hashable {
    var id, subject, topic, date, teacher, type: String
    var subjectID = ""

    /// KRÉTA supplies a day, not an exact lesson time. Match the subject on that
    /// day without guessing which period a test belongs to.
    func matches(_ lesson: Lesson) -> Bool {
        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "hu_HU"))
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        guard !date.isEmpty, date == lesson.date else { return false }
        if !subjectID.isEmpty, !lesson.subjectID.isEmpty { return subjectID == lesson.subjectID }
        return !normalized(subject).isEmpty && normalized(subject) == normalized(lesson.subject)
    }

    static func parse(_ data: JSON) -> [AnnouncedTest] {
        let today = Day.today
        return data.rows.enumerated().map { i, t in
            let id = t["Uid", "uid", "Id", "id"].text
            let subject = t["Tantargy"].name
            return AnnouncedTest(
                id: id.isEmpty ? "\(i)" : id,
                subject: subject.isEmpty ? (t["TantargyNeve"].text.isEmpty ? "Számonkérés" : t["TantargyNeve"].text) : subject,
                topic: t["Temaja", "Tema", "Nev"].text,
                date: Day.of(t["Datum", "SzamonkeresDatuma"]),
                teacher: t["RogzitoTanarNeve", "TanarNeve"].text,
                type: t["Modja", "Tipus"].text,
                subjectID: t["Tantargy"]["Uid"].text.isEmpty ? t["TantargyUid"].text : t["Tantargy"]["Uid"].text)
        }.sorted { a, b in
            // Closest upcoming first, then past ones newest first.
            let au = a.date >= today, bu = b.date >= today
            if au && bu { return a.date < b.date }
            if au != bu { return au }
            return a.date > b.date
        }
    }
}

struct Absence: Identifiable, Hashable {
    var id, subject, date, type, status: String
    var minutes: Int
    var justified: Bool
    var lessonNumber: Int?

    static func parse(_ data: JSON) -> [Absence] {
        data.rows.enumerated().map { i, a in
            let status = a["IgazolasAllapota"].text
            let type = a["Tipus"].text
            return Absence(
                id: a["Uid"].text.isEmpty ? "\(i)" : a["Uid"].text,
                subject: a["Tantargy"].name, date: Day.of(a["Datum"]),
                type: type.isEmpty ? "Hiányzás" : type, status: status,
                minutes: Int(a["KesesPercben"].number ?? 0),
                justified: status.lowercased() == "igazolt",
                lessonNumber: a["Ora"]["Oraszam"].number.map { Int($0) })
        }.sorted { $0.date > $1.date }
    }
}

struct Message: Identifiable, Hashable {
    var id, subject, sender, date, text: String
    var read: Bool
    var attachments: [String]
    var recipients: [String]

    static func parse(_ data: JSON) -> [Message] {
        data.rows.enumerated().map { i, m in
            let c = m["uzenet"].isNull ? m : m["uzenet"]
            let subject = c["targy", "uzenetTargy"].isNull ? m["Cim"].text : c["targy", "uzenetTargy"].text
            return Message(
                id: m["azonosito", "Uid"].isNull ? "\(i)" : m["azonosito", "Uid"].text,
                subject: subject.isEmpty ? "Nincs tárgy" : subject,
                sender: c["feladoNev", "uzenetFeladoNev"].isNull ? m["RogzitoNeve", "KeszitoTanarNeve"].text : c["feladoNev", "uzenetFeladoNev"].text,
                date: c["kuldesDatum", "uzenetKuldesDatum"].isNull ? m["ErvenyessegKezdete", "Datum", "KeszitesDatuma"].text : c["kuldesDatum", "uzenetKuldesDatum"].text,
                text: c["szoveg", "tartalom"].isNull ? m["TartalomText", "Tartalom", "TartalomFormazott"].plain : c["szoveg", "tartalom"].plain,
                read: m["isElolvasva", "elolvasva", "isOlvasott", "olvasott", "TartalomText"].truthy,
                attachments: c["csatolmanyok"].rows.map { a in
                    let n = a["fajlNev", "nev", "Nev"].text
                    return n.isEmpty ? "Melléklet" : n
                },
                recipients: c["cimzettLista"].rows.map { $0["nev", "Nev"].text }.filter { !$0.isEmpty })
        }.sorted { $0.date > $1.date }
    }

    var day: String { Day.of(date) }
}

enum MessageFolder: String, CaseIterable, Identifiable {
    case messagesInbox, messagesSent, messagesDeleted
    var id: Self { self }
    var label: String { switch self { case .messagesInbox: "Beérkezett"; case .messagesSent: "Elküldött"; case .messagesDeleted: "Törölt" } }
    var icon: String { switch self { case .messagesInbox: "tray"; case .messagesSent: "paperplane"; case .messagesDeleted: "trash" } }
}

struct Note: Identifiable, Hashable {
    enum Tone { case neutral, praise, warning, deficit, notice }
    var id, title, author, date, type, text: String
    var tone: Tone

    static func parse(notes: JSON, notices: JSON) -> [Note] {
        var out: [Note] = []
        for n in notes.rows {
            let type = n["Tipus"].text
            let title = n["Cim"].text.isEmpty ? (type.isEmpty ? "Tanári feljegyzés" : type) : n["Cim"].text
            let hay = "\(type) \(title)".lowercased()
            let has = { (words: [String]) in words.contains { hay.contains($0) } }
            let tone: Tone = has(["dicsér", "dicser"]) ? .praise
                : has(["figyelmeztet", "intés", "intes", "megrovás", "megrovas"]) ? .warning
                : has(["hiány", "hiany", "hazifeladat"]) ? .deficit : .neutral
            out.append(Note(
                id: n["Uid", "uid", "Id", "id"].isNull ? "n\(out.count)" : n["Uid", "uid", "Id", "id"].text,
                title: title, author: n["KeszitoTanarNeve", "RogzitoTanarNeve", "TanarNeve"].text,
                date: Day.of(n["Datum", "KeszitesDatuma", "RogzitesDatuma"]),
                type: type.isEmpty ? "Feljegyzés" : type,
                text: n["Tartalom", "TartalomFormazott", "Szoveg"].plain, tone: tone))
        }
        for n in notices.rows {
            let author = n["RogzitoNeve", "KeszitoTanarNeve"].text
            out.append(Note(
                id: n["Uid", "uid", "Id", "id"].isNull ? "f\(out.count)" : n["Uid", "uid", "Id", "id"].text,
                title: n["Cim"].text.isEmpty ? "Faliújság hír" : n["Cim"].text,
                author: author.isEmpty ? "Iskola" : author,
                date: Day.of(n["ErvenyessegKezdete", "Datum", "KeszitesDatuma"]),
                type: "Faliújság", text: n["TartalomText", "Tartalom", "Szoveg"].plain, tone: .notice))
        }
        return out.sorted { $0.date > $1.date }
    }
}

struct Consultation: Identifiable, Hashable {
    var id, teacher, subject, start, end, room: String
    var booked: String?
    var raw: JSON

    static func parse(_ data: JSON) -> [Consultation] {
        data.rows.flatMap { group -> [Consultation] in
            guard let hours = group["Fogadoorak"].array else {
                return [Consultation(id: group["Uid", "uid", "id", "azonosito"].text, teacher: group["tanarNev", "TanarNeve"].text,
                                     subject: group["tantargyNev"].text, start: group["idopont", "KezdetIdopont"].text,
                                     end: "", room: group["teremNev", "TeremNeve"].text, booked: nil, raw: group)]
            }
            return hours.filter(\.isObject).map { h in
                let booked = h["Idopontok"].rows.filter { $0["IsJelentkeztem"].bool == true }.map { Format.time($0["KezdoIdopont"].text) }
                return Consultation(id: h["Uid"].text, teacher: group["Tanar"].name, subject: "",
                                    start: h["KezdoIdopont"].text, end: h["VegIdopont"].text, room: h["Terem"].name,
                                    booked: booked.isEmpty ? nil : booked.joined(separator: ", "), raw: h)
            }
        }.sorted { $0.start < $1.start }
    }
}

struct LepEvent: Identifiable, Hashable {
    var id, title, place, date, description: String
    var duration: Int?
    var canDecide: Bool
    var permitted: Bool

    static func parse(_ data: JSON) -> [LepEvent] {
        data.rows.enumerated().map { i, e in
            let title = e["eloadasCim", "Cim"].text
            return LepEvent(id: e["eloadasId"].isNull ? "\(i)" : e["eloadasId"].text,
                            title: title.isEmpty ? "LEP esemény" : title, place: e["helyszin"].text,
                            date: Day.of(e["datum", "Datum"]), description: e["leiras"].plain,
                            duration: e["idotartam"].number.map { Int($0) },
                            canDecide: e["engedelyezheto"].truthy, permitted: e["engedelyezve"].truthy)
        }
    }
}

struct ClassAverage: Identifiable {
    var id: String
    var subject: String
    var student: Double
    var group: Double

    static func parse(_ data: JSON) -> [ClassAverage] {
        data.rows.compactMap { r in
            guard let s = r["TanuloAtlag"].number, let g = r["OsztalyCsoportAtlag"].number, !r["Tantargy"].name.isEmpty else { return nil }
            return ClassAverage(id: r["Uid"].text, subject: r["Tantargy"].name, student: s, group: g)
        }
    }
}

struct SchoolYearEvent: Identifiable, Hashable {
    var date, description: String
    var id: String { date + description }

    static func parse(_ data: JSON) -> [SchoolYearEvent] {
        data.rows.map { SchoolYearEvent(date: Day.of($0["Datum"]), description: $0["Naptipus"]["Leiras", "Nev"].text) }
            .filter { !$0.date.isEmpty && $0.description.range(of: "Utolsó tanítási nap|Első tanítási nap|Első félév vége", options: [.regularExpression, .caseInsensitive]) != nil }
            .sorted { $0.date < $1.date }
    }
}
