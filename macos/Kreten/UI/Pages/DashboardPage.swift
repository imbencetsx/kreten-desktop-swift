import SwiftUI

/// Two columns when there's room, otherwise stacked.
struct AdaptiveColumns<Leading: View, Trailing: View>: View {
    var trailingWidth: CGFloat = 330
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) { leading }.frame(minWidth: 440)
                VStack(spacing: 16) { trailing }.frame(width: trailingWidth)
            }
            VStack(spacing: 16) { leading; trailing }
        }
    }
}

struct DashboardPage: View {
    @Environment(AppModel.self) private var model
    @State private var detail: Lesson?

    var body: some View {
        let d = model.diary
        let today = Day.today
        // Today's lessons, or the next school day's when today has none.
        let schoolDay = d.lessons.contains { $0.date == today } ? today : (d.lessons.first { $0.date > today }?.date ?? today)
        let schedule = d.lessons.filter { $0.date == schoolDay }
        let homework = d.homework.filter { !model.isDone($0) && ($0.date.isEmpty || $0.date >= today) }
        let tests = d.tests.filter { $0.date.isEmpty || $0.date >= today }

        PageScaffold(eyebrow: Format.longDate(Date()), title: "Szia, \(model.firstName)!") {
            Button("Heti órarend") { model.page = .timetable }
                .buttonStyle(.glass)
        } content: {
            AdaptiveColumns {
                LiveLessonCard()
                Card {
                    CardHeader(title: schoolDay == today ? "Mai órák" : "\(Format.weekday(schoolDay)) órái", count: schedule.count) {
                        if schoolDay != today { Text(Format.day(schoolDay)).font(.mono(12)).foregroundStyle(.secondary) }
                    }
                    if schedule.isEmpty {
                        EmptyState(title: "Nincs ismert következő tanóra.")
                    } else {
                        TimelineView(.periodic(from: .now, by: 30)) { ctx in
                            let now = model.schoolNow(ctx.date)
                            VStack(spacing: 0) {
                                ForEach(schedule) { l in
                                    LessonRow(lesson: l, active: !l.cancelled && (l.startDate ?? .distantFuture) <= now && now < (l.endDate ?? .distantPast)) {
                                        detail = l
                                    }
                                }
                            }
                        }
                    }
                }
                Card {
                    CardHeader(title: "Házi feladatok", count: homework.count) { LinkButton(title: "Mind") { model.page = .homework } }
                    if homework.isEmpty {
                        EmptyState(title: "Nincs közelgő házi feladat.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(homework.prefix(4)) { h in
                                RowButton { model.page = .homework } content: {
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(Format.day(h.date)).font(.mono(12)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(h.subject).font(.callout.weight(.medium))
                                            Text(h.text).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }
                }
            } trailing: {
                AverageCard()
                Card {
                    CardHeader(title: "Legutóbbi jegyek") { LinkButton(title: "Mind") { model.page = .grades } }
                    if d.grades.isEmpty {
                        EmptyState(title: "Még nincs értékelés.")
                    } else {
                        ForEach(d.grades.prefix(5)) { g in
                            HStack(spacing: 10) {
                                GradeBadge(grade: g, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(g.subject).font(.callout.weight(.medium)).lineLimit(1)
                                    Text(g.topic.isEmpty ? g.type : g.topic).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Format.day(g.date)).font(.mono(11)).foregroundStyle(.secondary)
                                    Text("\(Int(g.weight))%").font(.mono(11)).foregroundStyle(g.weight > 100 ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                                }
                            }
                        }
                    }
                }
                Card {
                    CardHeader(title: "Dolgozatok", count: tests.count) { LinkButton(title: "Mind") { model.page = .tests } }
                    if tests.isEmpty {
                        EmptyState(title: "Nincs bejelentett számonkérés.")
                    } else {
                        ForEach(tests.prefix(4)) { t in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(Format.day(t.date)).font(.mono(12)).foregroundStyle(.orange).frame(width: 64, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.subject).font(.callout.weight(.medium))
                                    if !t.topic.isEmpty { Text(t.topic).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                            }
                        }
                    }
                }
                if !d.schoolYear.isEmpty {
                    Card {
                        CardHeader("Tanév")
                        ForEach(d.schoolYear) { e in
                            HStack(alignment: .firstTextBaseline) {
                                Text(e.description).font(.callout).lineLimit(1)
                                Spacer()
                                Text(Format.day(e.date, year: true)).font(.mono(12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $detail) { LessonDetail(lesson: $0) }
    }
}

/// What's happening right now, with a live countdown and a thin progress line.
struct LiveLessonCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = model.schoolNow(ctx.date)
            let live = LiveStatus.compute(model.diary.lessons, now: now)
            let color: Color = live.kind == .breakTime ? .orange : .accentColor
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if live.kind == .lesson { Circle().fill(.green).frame(width: 6, height: 6) }
                            Text(live.label).font(.mono(11, .medium)).foregroundStyle(.secondary)
                        }
                        Text(live.title)
                            .font(.system(size: 26, weight: .semibold, design: model.prefs.titleFont.design))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(live.details).font(.mono(12)).foregroundStyle(.secondary)
                        if !live.secondary.isEmpty { Text(live.secondary).font(.callout).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                    trailing(live, now: now)
                }
                if live.kind == .lesson || live.kind == .breakTime {
                    Meter(value: live.progress(at: now), color: color, height: 4)
                }
            }
            .padding(18)
            .panel()
            .contentShape(.rect)
            .onTapGesture { model.page = .timetable }
        }
    }

    @ViewBuilder private func trailing(_ live: LiveStatus, now: Date) -> some View {
        if let end = live.end, live.kind == .upcoming, end.timeIntervalSince(now) > 4 * 3600 {
            // A countdown to a lesson days away is noise; show when it is instead.
            VStack(alignment: .trailing, spacing: 4) {
                Text(Day.string(end) == Day.add(Day.today, 1) ? "Holnap" : Format.weekday(Day.string(end)))
                    .font(.system(size: 22, weight: .semibold))
                Text("\(Format.day(Day.string(end))) · \(Format.time(end))").font(.mono(12)).foregroundStyle(.secondary)
            }
        } else if let end = live.end, live.kind != .empty {
            Countdown(remaining: end.timeIntervalSince(now), caption: live.kind == .upcoming ? "kezdésig" : "hátra")
        }
    }
}

struct Countdown: View {
    var remaining: TimeInterval
    var caption: String

    var body: some View {
        let total = max(0, Int(remaining.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        VStack(alignment: .trailing, spacing: 2) {
            Text(h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s))
                .font(.mono(30, .medium))
                .contentTransition(.numericText(countsDown: true))
            Text(caption.uppercased()).font(.mono(10, .medium)).foregroundStyle(.secondary)
        }
    }
}

struct AverageCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let grades = model.diary.grades
        let avg = grades.average
        Card {
            Text("TANÉVI ÁTLAG").font(.mono(11, .medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                PrivateText(text: Format.decimal(avg), font: .system(size: 40, weight: .semibold))
                Spacer()
                if let e = estimatedGrade(avg, thresholds: model.prefs.gradeThresholds), !model.gradesHidden {
                    Text("≈ \(e)").font(.mono(14, .medium)).foregroundStyle(gradeColor(e))
                }
            }
            Meter(value: model.gradesHidden ? 0 : ((avg ?? 1) - 1) / 4, color: model.gradesHidden ? .secondary : averageColor(avg), height: 4)
            HStack {
                Text("\(grades.count) jegy · \(grades.bySubject.count) tárgy").font(.mono(11)).foregroundStyle(.secondary)
                Spacer()
                LinkButton(title: "Statisztikák") { model.page = .statistics }
            }
        }
    }
}

struct LessonRow: View {
    var lesson: Lesson
    var active: Bool
    var action: () -> Void

    var body: some View {
        RowButton(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(lesson.number > 0 ? "\(lesson.number)" : "–")
                    .font(.mono(12, .medium))
                    .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 16, alignment: .trailing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lesson.subject).font(.callout.weight(active ? .semibold : .medium))
                        .strikethrough(lesson.cancelled)
                        .foregroundStyle(lesson.cancelled ? .secondary : .primary)
                    Text(lesson.displayTeacher).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if lesson.cancelled { Pill(text: "elmarad", color: .red) }
                else if !lesson.substitute.isEmpty { Pill(text: "helyettesítés", color: .orange) }
                Text(lesson.room).font(.mono(12)).foregroundStyle(.secondary).frame(minWidth: 36, alignment: .trailing)
                Text(lesson.timeRange).font(.mono(12)).foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
        }
        .background(active ? Color.accentColor.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
    }
}

struct LessonDetail: View {
    var lesson: Lesson
    @Environment(AppModel.self) private var model

    var body: some View {
        DetailSheet(title: lesson.subject, subtitle: "\(Format.weekday(lesson.date)), \(Format.day(lesson.date, year: true))") {
            HStack {
                Pill(text: lesson.cancelled ? "elmarad" : (lesson.state.isEmpty ? "tanóra" : lesson.state.lowercased()), color: lesson.cancelled ? .red : .secondary)
                if lesson.number > 0 { Pill(text: "\(lesson.number). óra") }
            }
            InfoGrid(rows: [
                ("Időpont", lesson.timeRange),
                ("Tanár", lesson.teacher),
            ] + (lesson.substitute.isEmpty ? [] : [("Helyettesítő", lesson.substitute)]) + [
                ("Terem", lesson.room),
                ("Téma", lesson.topic.isEmpty ? "Még nincs megadva" : lesson.topic),
            ])
            let tests = model.diary.tests.filter { $0.matches(lesson) }
            if !tests.isEmpty {
                Divider()
                Text("Aznap bejelentett dolgozat").font(.headline)
                ForEach(tests) { AnnouncedTestRow(test: $0) }
            }
        }
    }
}
