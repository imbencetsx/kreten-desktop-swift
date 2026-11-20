import SwiftUI

private enum TestPeriod: String, CaseIterable, Identifiable {
    case upcoming = "Közelgő", past = "Korábbi", all = "Mind"
    var id: Self { self }
}

struct TestsPage: View {
    @Environment(AppModel.self) private var model
    @State private var period = TestPeriod.upcoming
    @State private var query = ""

    var body: some View {
        let today = Day.today
        let q = query.searchKey
        let tests = model.diary.tests.filter { test in
            let upcoming = test.date.isEmpty || test.date >= today
            let inPeriod = period == .all || (period == .upcoming ? upcoming : !upcoming)
            return inPeriod && (q.isEmpty || "\(test.subject) \(test.topic) \(test.teacher) \(test.type)".searchKey.contains(q))
        }
        let groups = Dictionary(grouping: tests, by: \.date).sorted { a, b in
            if a.key.isEmpty { return false }
            if b.key.isEmpty { return true }
            return period == .past ? a.key > b.key : a.key < b.key
        }

        PageScaffold(eyebrow: "Bejelentett számonkérések", title: "Dolgozatok",
                     subtitle: "Témák, időpontok és tanárok a KRÉTA alapján.") {
            GlassSearchField(prompt: "Tantárgy, téma vagy tanár", text: $query)
        } content: {
            HStack {
                Picker("Időszak", selection: $period) {
                    ForEach(TestPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                Spacer()
                Text("\(tests.count) dolgozat").font(.mono(12)).foregroundStyle(.secondary)
            }
            if groups.isEmpty {
                Card {
                    EmptyState(title: q.isEmpty ? "Nincs megjeleníthető dolgozat." : "Nincs találat.",
                               text: q.isEmpty ? "A bejelentett dolgozatok itt és az órarendben jelennek meg." : "Próbálj másik keresést vagy időszakot.")
                }
            }
            ForEach(groups, id: \.key) { day, items in
                Card {
                    CardHeader(title: day.isEmpty ? "Időpont nélkül" : "\(Format.weekday(day)), \(Format.day(day, year: true))", count: items.count) {
                        if day == today { Pill(text: "Ma", color: .orange) }
                        else if day == Day.add(today, 1) { Pill(text: "Holnap", color: .orange) }
                        else if !day.isEmpty && day < today { Pill(text: "Korábbi") }
                    }
                    ForEach(items) { test in
                        AnnouncedTestRow(test: test)
                        if test.id != items.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

/// Used both by the dedicated page and the timetable's day/lesson sheets.
struct AnnouncedTestRow: View {
    var test: AnnouncedTest

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "pencil.and.outline")
                .foregroundStyle(.orange)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(test.subject).font(.headline)
                Text(test.topic.isEmpty ? "A téma még nincs megadva." : test.topic)
                    .font(.callout).foregroundStyle(.secondary)
                let detail = [test.type, test.teacher].filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .textSelection(.enabled)
    }
}
