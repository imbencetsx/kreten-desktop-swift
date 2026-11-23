import SwiftUI

struct TimetablePage: View {
    @Environment(AppModel.self) private var model
    /// On weekends the upcoming week is the useful one.
    private static var homeOffset: Int { Day.isWeekend(Day.today) ? 1 : 0 }
    @State private var offset = TimetablePage.homeOffset
    @State private var query = ""
    @State private var fetched: [String: [Lesson]] = [:] // keyed by Monday
    @State private var loading = false
    @State private var detail: Lesson?

    private var monday: String { Day.add(Day.monday(of: Day.today), offset * 7) }
    private var days: [String] { (0..<7).map { Day.add(monday, $0) } }

    /// The sync caches the previous week through ~3 weeks ahead; anything else is fetched on demand.
    private var cachedWeek: Bool { (-1...2).contains(offset) }

    private var lessons: [Lesson] {
        let source = cachedWeek ? model.diary.lessons : (fetched[monday] ?? [])
        let q = query.searchKey
        return source.filter { days.contains($0.date) && (q.isEmpty || "\($0.subject) \($0.teacher) \($0.room)".searchKey.contains(q)) }
    }

    var body: some View {
        let lessons = lessons
        let visibleDays = lessons.contains { Day.isWeekend($0.date) } ? days : Array(days.prefix(5))

        PageScaffold(eyebrow: "Heti nézet", title: "Órarend") {
            HStack(spacing: 10) {
                GlassSearchField(prompt: "Szűrés", text: $query).frame(width: 220)
                WeekSwitcher(offset: $offset, home: Self.homeOffset, label: "\(Format.day(days[0], year: true)) – \(Format.day(days[4]))")
            }
        } content: {
            if loading {
                HStack { ProgressView().controlSize(.small); Text("Az órarend betöltése…").foregroundStyle(.secondary) }
            }
            // A shared sampling region, with less merge distance than the 8pt
            // row gap, keeps every lesson a separate native glass surface.
            GlassEffectContainer(spacing: 4) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(visibleDays, id: \.self) { day in
                        DayColumn(day: day, lessons: lessons.filter { $0.date == day }, loading: loading) { detail = $0 }
                    }
                }
            }
            .animation(.smooth, value: offset)
        }
        .task(id: offset) { await load() }
        .sheet(item: $detail) { LessonDetail(lesson: $0) }
    }

    private func load() async {
        guard !cachedWeek, fetched[monday] == nil else { return }
        loading = true
        defer { loading = false }
        if let result = await model.timetable(weekOf: monday) {
            withAnimation(.smooth) { fetched[monday] = result }
        }
    }
}

struct WeekSwitcher: View {
    @Binding var offset: Int
    var home: Int
    var label: String
    @Namespace private var ns

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button { offset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 18, height: 18) }
                    .buttonStyle(.glassy).buttonBorderShape(.circle)
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Text(label)
                    .font(.mono(12, .medium))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .surface(.capsule)
                Button { offset += 1 } label: { Image(systemName: "chevron.right").frame(width: 18, height: 18) }
                    .buttonStyle(.glassy).buttonBorderShape(.circle)
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                if offset != home {
                    Button(home == 0 ? "Ez a hét" : "Jövő hét") { offset = home }
                        .buttonStyle(.glassy)
                        .glassEffectID("today", in: ns)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.bouncy, value: offset == home)
    }
}

struct DayColumn: View {
    var day: String
    var lessons: [Lesson]
    var loading: Bool
    var open: (Lesson) -> Void
    @Environment(AppModel.self) private var model
    @State private var showTests = false

    var body: some View {
        let isToday = day == Day.today
        let tests = model.diary.tests.filter { $0.date == day }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.weekday(day)).font(.headline).foregroundStyle(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    Text(Format.day(day)).font(.mono(11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            if !tests.isEmpty {
                Button { showTests = true } label: {
                    Label("\(tests.count) dolgozat", systemImage: "pencil.and.outline")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .surface(.rect(cornerRadius: 10), tint: .orange.opacity(0.2), interactive: true)
                .help(tests.map { "\($0.subject): \($0.topic)" }.joined(separator: "\n"))
            }
            if lessons.isEmpty {
                Text(loading ? "Betöltés…" : "Nincs tanóra")
                    .font(.callout).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .panel(radius: 12)
            }
            TimelineView(.every(30, paused: !model.windowVisible)) { ctx in
                let now = model.schoolNow(ctx.date)
                VStack(spacing: 8) {
                    ForEach(lessons) { l in
                        LessonTile(lesson: l, tests: tests.filter { $0.matches(l) }, current: l.isActive(at: now)) { open(l) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .sheet(isPresented: $showTests) {
            DetailSheet(title: "Dolgozatok", subtitle: "\(Format.weekday(day)), \(Format.day(day, year: true))") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(tests) { AnnouncedTestRow(test: $0) }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
    }
}

struct LessonTile: View {
    var lesson: Lesson
    var tests: [AnnouncedTest]
    var current: Bool
    var action: () -> Void

    var body: some View {
        let tint: Color? = lesson.cancelled ? .red : !lesson.substitute.isEmpty ? .orange : current ? Color.accentColor : !tests.isEmpty ? .orange : nil
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(lesson.number > 0 ? "\(lesson.number)." : "")
                        .font(.mono(11, .semibold)).foregroundStyle(tint ?? .secondary)
                    Spacer()
                    Text(lesson.timeRange).font(.mono(11)).foregroundStyle(.secondary)
                }
                Text(lesson.subject).font(.callout.weight(.semibold)).lineLimit(2).strikethrough(lesson.cancelled)
                Text(lesson.displayTeacher).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 4) {
                    Text(lesson.room.isEmpty ? "—" : lesson.room)
                    if lesson.cancelled { Text("· elmarad").foregroundStyle(.red) }
                    else if !lesson.substitute.isEmpty { Text("· helyettesítés").foregroundStyle(.orange) }
                }
                .font(.mono(11)).foregroundStyle(.secondary).lineLimit(1)
                if !tests.isEmpty {
                    Label("\(tests.first?.subject ?? lesson.subject) · dolgozat", systemImage: "pencil.and.outline")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tests.map { $0.topic.isEmpty ? $0.type : $0.topic }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 12))
            .surface(.rect(cornerRadius: 12), tint: tint?.opacity(current ? 0.2 : 0.12), interactive: true)
        }
        .buttonStyle(.plain)
    }
}
