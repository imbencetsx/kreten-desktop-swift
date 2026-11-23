import SwiftUI

// MARK: Progress

struct SchoolProgressPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.every(60, paused: !model.windowVisible)) { ctx in
            let now = ctx.date
            let cal = model.diary.calendar
            let week = SchoolProgress.week(now: now)
            let brk = SchoolProgress.nextBreak(cal, now: now)
            let year = SchoolProgress.year(cal, now: now)

            PageScaffold(eyebrow: "Haladás", title: "Mennyi van még hátra?",
                         subtitle: "A hét, a következő szünet és a tanév — a suli naptára alapján.") {
                HStack(alignment: .top, spacing: 14) {
                    RingCard(title: "A hét", value: week.span.fraction, color: Color.accentColor,
                             headline: week.weekend ? "Hétvége van!" : "\(week.span.schoolDaysLeft) tanítási nap",
                             detail: week.weekend ? "Hétfőig \(duration(week.span.remaining))" : "Péntek estig \(duration(week.span.remaining))")
                    RingCard(title: brk.current?.name ?? brk.next?.name ?? "Következő szünet", value: brk.span.fraction, color: .orange,
                             headline: brk.current != nil ? "Most szünet van" : brk.next == nil ? "Nincs több szünet" : "\(brk.span.remainingDays) nap",
                             detail: brk.current.map { "Vége: \(Format.day($0.end))" }
                                ?? brk.next.map { "\(brk.span.schoolDaysLeft) tanítási nap · \(Format.day($0.start))-tól" + ($0.estimated ? " (becsült)" : "") } ?? "")
                    RingCard(title: "Tanév", value: year.span.fraction, color: .green,
                             headline: year.phase == .after ? "Vége a tanévnek!" : year.phase == .before ? "Még nem kezdődött" : "\(year.span.schoolDaysLeft) tanítási nap",
                             detail: "Utolsó tanítási nap: \(Format.day(cal.lastDay, year: true))" + (cal.lastEstimated ? " (becsült)" : ""))
                }
                Card {
                    CardHeader("Szünetek")
                    ForEach(cal.breaks, id: \.self) { b in
                        let past = b.end < Day.today
                        HStack {
                            Image(systemName: past ? "checkmark.circle.fill" : "calendar")
                                .foregroundStyle(past ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                            Text(b.name).font(.callout.weight(.medium))
                            if b.estimated { Pill(text: "becsült", color: .secondary) }
                            Spacer()
                            Text("\(Format.day(b.start)) – \(Format.day(b.end))").font(.mono(11)).foregroundStyle(.secondary)
                        }
                        .opacity(past ? 0.55 : 1)
                    }
                    if cal.breaks.isEmpty { EmptyState(title: "Nincs ismert szünet.") }
                }
            }
        }
    }

    private func duration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, d = h / 24
        return d > 0 ? "\(d) nap \(h % 24) óra" : "\(h) óra \((Int(t) % 3600) / 60) perc"
    }
}

struct RingCard: View {
    var title: String
    var value: Double
    var color: Color
    var headline: String
    var detail: String
    @State private var shown = 0.0

    var body: some View {
        Card(padding: 20) {
            Text(title.uppercased()).font(.mono(11, .medium)).foregroundStyle(.secondary)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((value * 100).rounded()))%")
                    .font(.mono(28, .medium))
                    .contentTransition(.numericText())
            }
            .frame(width: 128, height: 128)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            Text(headline).font(.title3.weight(.semibold))
            Text(detail).font(.mono(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { withAnimation(.smooth(duration: 0.6)) { shown = value } }
        .onChange(of: value) { _, v in withAnimation(.smooth) { shown = v } }
    }
}

// MARK: Homework

struct HomeworkPage: View {
    @Environment(AppModel.self) private var model
    @State private var showDone = false
    @State private var query = ""

    var body: some View {
        let q = query.searchKey
        let match = { (s: String) in q.isEmpty || s.searchKey.contains(q) }
        let today = Day.today
        let homework = model.diary.homework.filter { match("\($0.subject) \($0.text)") && (showDone || !model.isDone($0)) }
        let tests = model.diary.tests.filter { match("\($0.subject) \($0.topic)") }
        let grouped = Dictionary(grouping: homework, by: \.date).sorted { $0.key < $1.key }

        PageScaffold(eyebrow: "Feladatok és dolgozatok", title: "A következő lépés.",
                     subtitle: "Legyen időd felkészülni. És időd minden másra is.") {
            HStack(spacing: 12) {
                Toggle("Elkészültek is", isOn: $showDone.animation(.smooth)).toggleStyle(.switch).controlSize(.small)
                GlassSearchField(prompt: "Keresés…", text: $query).frame(width: 220)
            }
        } content: {
            AdaptiveColumns(trailingWidth: 360) {
                Card {
                    CardHeader("Házi feladatok", count: homework.count)
                    if homework.isEmpty {
                        EmptyState(title: "Minden feladattal megvagy.", text: "A kész jelölés csak ezen a Macen tárolódik.")
                    }
                    ForEach(grouped, id: \.key) { day, items in
                        Text(dueLabel(day, today: today))
                            .font(.mono(11, .medium)).foregroundStyle(day < today ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                            .padding(.top, 6)
                        ForEach(items) { HomeworkRow(homework: $0) }
                    }
                }
            } trailing: {
                Card {
                    CardHeader("Dolgozatok", count: tests.count)
                    if tests.isEmpty { EmptyState(title: "Nincs bejelentett dolgozat.") }
                    ForEach(tests) { t in
                        let past = t.date < today
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(t.subject).font(.callout.weight(.semibold))
                                Spacer()
                                Pill(text: past ? "Múltbeli" : Format.day(t.date), color: past ? .secondary : .orange)
                            }
                            if !t.topic.isEmpty { Text(t.topic).font(.callout).foregroundStyle(.secondary) }
                            Text([t.type, t.teacher].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .opacity(past ? 0.6 : 1)
                    }
                }
            }
        }
    }

    private func dueLabel(_ day: String, today: String) -> String {
        if day.isEmpty { return "NINCS HATÁRIDŐ" }
        if day == today { return "MA" }
        if day == Day.add(today, 1) { return "HOLNAP" }
        return "\(Format.weekday(day)), \(Format.day(day))".uppercased()
    }
}

struct HomeworkRow: View {
    var homework: Homework
    @Environment(AppModel.self) private var model

    var body: some View {
        let done = model.isDone(homework)
        HStack(alignment: .top, spacing: 12) {
            Button {
                if !homework.doneInKreta { model.toggleHomework(homework) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(homework.doneInKreta)
            .help(homework.doneInKreta ? "KRÉTA-ban kész" : done ? "Visszaállítás" : "Késznek jelölöm (csak helyben)")
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(homework.subject).font(.callout.weight(.semibold))
                    if homework.doneInKreta { Pill(text: "KRÉTA-ban kész", color: .green) }
                }
                Text(homework.text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .strikethrough(done, color: .secondary)
                Text([homework.teacher, homework.created.isEmpty ? "" : "Feladva: \(Format.day(homework.created))"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .opacity(done ? 0.6 : 1)
        .animation(.smooth, value: done)
    }
}

// MARK: Absences

struct AbsencesPage: View {
    @Environment(AppModel.self) private var model
    @State private var filter = 0 // 0 all, 1 justified, 2 other

    var body: some View {
        let all = model.diary.absences
        let shown = all.filter { filter == 0 || (filter == 1) == $0.justified }
        let grouped = Dictionary(grouping: shown, by: \.date).sorted { $0.key > $1.key }

        PageScaffold(eyebrow: "Jelenlét és mulasztások", title: "Hiányzások") {
            HStack(spacing: 14) {
                StatTile(label: "Mulasztások", value: "\(all.count)", note: "Rögzített bejegyzés")
                StatTile(label: "Igazolt", value: "\(all.filter(\.justified).count)", note: "Lezárt igazolások")
                StatTile(label: "Egyéb állapot", value: "\(all.filter { !$0.justified }.count)", note: "Igazolatlan vagy elbírálás alatt")
                StatTile(label: "Késések", value: "\(all.reduce(0) { $0 + $1.minutes })", note: "Perc összesen")
            }
            Card {
                CardHeader(title: "Mulasztásaid") {
                    Picker("Állapot", selection: $filter.animation(.smooth)) {
                        Text("Mind").tag(0); Text("Igazolt").tag(1); Text("Egyéb").tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                if shown.isEmpty {
                    EmptyState(title: "Nincs rögzített mulasztás.", text: "A szűrésnek megfelelő bejegyzések itt jelennek meg.")
                }
                ForEach(grouped, id: \.key) { day, items in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Format.day(day)).font(.mono(11))
                            Text(Format.weekday(day)).font(.mono(11)).foregroundStyle(.secondary)
                        }
                        .frame(width: 92, alignment: .leading)
                        VStack(spacing: 6) {
                            ForEach(items) { a in
                                HStack {
                                    if let n = a.lessonNumber { Text("\(n).").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 20) }
                                    Text(a.subject.isEmpty ? "—" : a.subject).font(.callout)
                                    if a.minutes > 0 { Text("· \(a.minutes) perc késés").font(.mono(11)).foregroundStyle(.secondary) }
                                    Spacer()
                                    Text(a.type).font(.caption).foregroundStyle(.secondary)
                                    Pill(text: a.justified ? "Igazolt" : (a.status.isEmpty ? "Igazolandó" : a.status), color: a.justified ? .green : .orange)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.4)
                }
            }
        }
    }
}
