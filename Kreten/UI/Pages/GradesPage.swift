import Charts
import SwiftUI

struct GradesPage: View {
    @Environment(AppModel.self) private var model
    @State private var period = GradePeriod.all
    @State private var query = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        let grades = model.diary.grades.period(period)
        let q = query.searchKey
        let groups = grades.bySubject.filter { q.isEmpty || $0.name.searchKey.contains(q) }

        PageScaffold(eyebrow: "Értékelések", title: "Jegyek") {
            Button("Statisztikák") { model.page = .statistics }.buttonStyle(.glassy)
        } content: {
            HStack {
                Picker("Időszak", selection: $period) {
                    ForEach(GradePeriod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                GlassSearchField(prompt: "Tantárgy", text: $query)
            }
            GradeStatsRow(grades: grades)
            Card {
                CardHeader(title: "Átlag alakulása") { Text("FUTÓ SÚLYOZOTT ÁTLAG").font(.mono(10, .medium)).foregroundStyle(.tertiary) }
                TrendChart(grades: grades)
            }
            if groups.isEmpty {
                Card { EmptyState(title: "Nincs értékelés ebben az időszakban.") }
            }
            LazyVStack(spacing: 8) {
                ForEach(groups) { group in
                    SubjectCard(group: group, expanded: expanded.contains(group.name)) {
                        withAnimation(.snappy(duration: 0.22)) {
                            if expanded.contains(group.name) { expanded.remove(group.name) } else { expanded.insert(group.name) }
                        }
                    }
                }
            }
        }
    }
}

struct GradeStatsRow: View {
    var grades: [Grade]
    var body: some View {
        let numeric = grades.numeric
        HStack(spacing: 12) {
            StatTile(label: "Átlag", value: Format.decimal(grades.average), note: "súlyozott", isPrivate: true)
            StatTile(label: "Jegyek", value: "\(grades.count)", note: "\(numeric.count) számjegyes")
            StatTile(label: "Tárgyak", value: "\(grades.bySubject.count)", note: "ebben az időszakban")
            StatTile(label: "Ötösök", value: "\(numeric.filter { $0.value == 5 }.count)", note: "\(numeric.isEmpty ? 0 : numeric.filter { $0.value == 5 }.count * 100 / numeric.count)% az összesből", isPrivate: true)
        }
    }
}

/// Running weighted average, one point per day, on a scale fitted to the data.
struct TrendChart: View {
    var grades: [Grade]
    @Environment(AppModel.self) private var model
    @State private var selected: Date?

    var body: some View {
        let points = grades.cumulativeTrend
        if points.count < 2 {
            EmptyState(title: "Még kevés jegy a grafikonhoz.")
        } else {
            let low = points.map(\.value).min() ?? 1
            let floor = max(1, (low - 0.3).rounded(.down))
            let hit = selected.flatMap { s in points.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) } }
            Chart {
                ForEach(points, id: \.date) { p in
                    AreaMark(x: .value("Dátum", p.date, unit: .day), yStart: .value("Alap", floor), yEnd: .value("Átlag", p.value))
                        .foregroundStyle(.linearGradient(colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Dátum", p.date, unit: .day), y: .value("Átlag", p.value))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let hit {
                    RuleMark(x: .value("Dátum", hit.date, unit: .day))
                        .foregroundStyle(Color.primary.opacity(0.2))
                    PointMark(x: .value("Dátum", hit.date, unit: .day), y: .value("Átlag", hit.value))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(40)
                        .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(spacing: 1) {
                                Text(Format.decimal(hit.value)).font(.mono(12, .semibold))
                                Text(Format.day(Day.string(hit.date))).font(.mono(10)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.regularMaterial, in: .rect(cornerRadius: 6))
                        }
                }
            }
            .chartYScale(domain: floor...5)
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .stride(by: floor >= 4 ? 0.25 : 0.5)) { v in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(Format.decimal(d)).font(.mono(10)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { v in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).locale(Format.hu)).font(.mono(10))
                }
            }
            .frame(height: 170)
            .blur(radius: model.gradesHidden ? 10 : 0)
            .overlay { if model.gradesHidden { Button("Felfedés") { model.revealGrades() }.buttonStyle(.glassy) } }
        }
    }
}

struct SubjectCard: View {
    var group: SubjectGroup
    var expanded: Bool
    var toggle: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let avg = group.average
        let estimate = estimatedGrade(avg, thresholds: model.prefs.gradeThresholds)
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.body.weight(.medium))
                        Text("\(group.grades.count) jegy" + (estimate.map { model.gradesHidden ? "" : " · ≈ \($0)" } ?? ""))
                            .font(.mono(11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !expanded {
                        HStack(spacing: 4) {
                            ForEach(group.grades.prefix(8)) { GradeBadge(grade: $0, size: 22) }
                        }
                    }
                    PrivateText(text: Format.decimal(avg), font: .mono(15, .semibold))
                        .foregroundStyle(model.gradesHidden ? Color.secondary : averageColor(avg))
                        .frame(minWidth: 44, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(group.grades) { g in
                        HStack(spacing: 12) {
                            GradeBadge(grade: g, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(g.topic.isEmpty ? (g.type.isEmpty ? "Értékelés" : g.type) : g.topic).font(.callout).lineLimit(2)
                                Text([g.type, g.teacher].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(Format.day(g.date)).font(.mono(11)).foregroundStyle(.secondary)
                            Text("\(Int(g.weight))%").font(.mono(11))
                                .foregroundStyle(g.weight > 100 ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                                .frame(width: 38, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        if g.id != group.grades.last?.id { Divider().opacity(0.5) }
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .panel(radius: 12)
    }
}

// MARK: Statistics

struct StatisticsPage: View {
    @Environment(AppModel.self) private var model
    @State private var period = GradePeriod.all
    @State private var subject = ""
    @State private var simGrade = 5
    @State private var simWeight = 100.0

    var body: some View {
        let all = model.diary.grades
        let filtered = all.period(period).filter { subject.isEmpty || $0.subject == subject }
        let groups = all.period(period).bySubject

        PageScaffold(eyebrow: "Statisztika", title: "Statisztikák") {
            Button("Jegyek") { model.page = .grades }.buttonStyle(.glassy)
        } content: {
            HStack(spacing: 12) {
                Picker("Időszak", selection: $period) {
                    ForEach(GradePeriod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Picker("Tantárgy", selection: $subject) {
                    Text("Minden tantárgy").tag("")
                    Divider()
                    ForEach(all.bySubject) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            GradeStatsRow(grades: filtered)
            HStack(alignment: .top, spacing: 12) {
                Card {
                    CardHeader("Átlag alakulása")
                    TrendChart(grades: filtered)
                }
                Card {
                    CardHeader("Eloszlás")
                    DistributionChart(grades: filtered)
                }
                .frame(maxWidth: 360)
            }
            Card {
                CardHeader("Tantárgyi átlagok")
                if groups.isEmpty {
                    EmptyState(title: "Nincs összehasonlítható adat.")
                } else {
                    VStack(spacing: 2) {
                        ForEach(groups) { g in
                            Button { subject = subject == g.name ? "" : g.name } label: {
                                HStack(spacing: 14) {
                                    Text(g.name).font(.callout).lineLimit(1).frame(width: 200, alignment: .leading)
                                    if let a = g.average {
                                        Meter(value: model.gradesHidden ? 0 : (a - 1) / 4, color: model.gradesHidden ? .secondary : averageColor(a), height: 5)
                                    } else {
                                        Text("nincs számjegyes jegy").font(.mono(11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    PrivateText(text: Format.decimal(g.average), font: .mono(12, .medium)).frame(width: 40, alignment: .trailing)
                                }
                                .padding(.vertical, 5).padding(.horizontal, 8)
                                .background(subject == g.name ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 6))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, -8)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                if !model.diary.classAverages.isEmpty {
                    Card {
                        CardHeader("Osztályátlagok")
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("TANTÁRGY"); Text("SAJÁT"); Text("OSZTÁLY"); Text("")
                            }
                            .font(.mono(10, .medium)).foregroundStyle(.secondary)
                            ForEach(model.diary.classAverages) { c in
                                GridRow {
                                    Text(c.subject).font(.callout).lineLimit(1)
                                    PrivateText(text: Format.decimal(c.student), font: .mono(12, .medium))
                                    PrivateText(text: Format.decimal(c.group), font: .mono(12)).foregroundStyle(.secondary)
                                    Text(model.gradesHidden ? "" : String(format: "%+.2f", c.student - c.group))
                                        .font(.mono(11)).foregroundStyle(c.student >= c.group ? .green : .orange)
                                }
                            }
                        }
                    }
                }
                WhatIfCard(base: filtered, subject: subject, grade: $simGrade, weight: $simWeight)
            }
        }
    }
}

struct DistributionChart: View {
    var grades: [Grade]
    @Environment(AppModel.self) private var model

    var body: some View {
        let numeric = grades.numeric
        let counts = (1...5).map { v in (v, numeric.filter { $0.value == v }.count) }
        let peak = counts.map(\.1).max() ?? 0
        Chart(counts, id: \.0) { v, count in
            BarMark(x: .value("Jegy", "\(v)"), y: .value("Darab", count), width: .ratio(0.55))
                .foregroundStyle(gradeColor(v))
                .clipShape(.rect(cornerRadius: 4))
                .annotation(position: .top, spacing: 4) {
                    Text("\(count)").font(.mono(11, .medium)).foregroundStyle(count == 0 ? .tertiary : .secondary)
                }
        }
        .chartYScale(domain: 0...max(1, Double(peak) * 1.2))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.mono(11, .medium)) }
        }
        .frame(height: 170)
        .blur(radius: model.gradesHidden ? 10 : 0)
        .overlay { if model.gradesHidden { Button("Felfedés") { model.revealGrades() }.buttonStyle(.glassy) } }
    }
}

/// Hypothetical next grade; never written to KRÉTA.
struct WhatIfCard: View {
    var base: [Grade]
    var subject: String
    @Binding var grade: Int
    @Binding var weight: Double
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = base.average
        let simulated = (base + [Grade(id: "sim", subject: subject, value: grade, display: "\(grade)", weight: weight,
                                       date: Day.today, topic: "", teacher: "", type: "", kind: "")]).average
        let delta = (simulated ?? 0) - (current ?? 0)
        Card {
            CardHeader("Mi lenne, ha…")
            Text(subject.isEmpty ? "Egy következő jegy hatása az átlagra" : "Egy következő jegy hatása · \(subject)")
                .font(.mono(11)).foregroundStyle(.secondary)
            Picker("Jegy", selection: $grade) {
                ForEach([1, 2, 3, 4, 5], id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Picker("Súly", selection: $weight) {
                ForEach([50.0, 100, 150, 200, 300], id: \.self) { Text("\(Int($0))%").tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                PrivateText(text: Format.decimal(current), font: .mono(16)).foregroundStyle(.secondary)
                Text("→").font(.mono(16)).foregroundStyle(.tertiary)
                PrivateText(text: Format.decimal(simulated), font: .system(size: 32, weight: .semibold))
                Spacer()
                if !model.gradesHidden, current != nil {
                    Text(String(format: "%+.2f", delta))
                        .font(.mono(13, .medium))
                        .foregroundStyle(delta >= 0 ? .green : .red)
                }
            }
            Text("Csak számítás, a naplóba nem kerül be.").font(.mono(10)).foregroundStyle(.tertiary)
        }
    }
}
