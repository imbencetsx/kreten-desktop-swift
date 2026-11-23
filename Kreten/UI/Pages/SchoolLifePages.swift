import SwiftUI

// MARK: Messages

struct MessagesPage: View {
    @Environment(AppModel.self) private var model
    @State private var folder = MessageFolder.messagesInbox
    @State private var query = ""
    @State private var selectedID: String?
    @State private var detail: Message?
    @State private var loading = false

    var body: some View {
        let q = query.searchKey
        let items = (model.diary.messages[folder] ?? []).filter { q.isEmpty || "\($0.subject) \($0.sender) \($0.text)".searchKey.contains(q) }

        PageScaffold(eyebrow: "Kapcsolat az iskolával", title: "Üzenetek", subtitle: "Az e-Ügyintézés hivatalos postafiókja.") {
            GlassSearchField(prompt: "Üzenet keresése…", text: $query)
        } content: {
            Picker("Mappa", selection: $folder.animation(.smooth)) {
                ForEach(MessageFolder.allCases) { f in Label(f.label, systemImage: f.icon).tag(f) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()

            HStack(alignment: .top, spacing: 14) {
                Card(padding: 10) {
                    if items.isEmpty {
                        EmptyState(title: "Ez a mappa most üres.", text: "A következő frissítéskor az új üzenetek is megjelennek.")
                    }
                    LazyVStack(spacing: 2) {
                        ForEach(items) { m in
                            MessageRow(message: m, selected: m.id == selectedID) { open(m) }
                        }
                    }
                }
                .frame(width: 340)

                Card(padding: 22) {
                    if let m = detail {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(m.subject).font(.title2.bold()).textSelection(.enabled)
                            HStack(spacing: 10) {
                                Avatar(name: m.sender, size: 30)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(m.sender.isEmpty ? "Ismeretlen feladó" : m.sender).font(.callout.weight(.semibold))
                                    Text(Day.timestamp(m.date).map { $0.formatted(date: .long, time: .shortened) } ?? Format.day(m.day, year: true))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if !m.recipients.isEmpty {
                                Text("Címzettek: \(m.recipients.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                            Divider()
                            Text(m.text.isEmpty ? "Az üzenet nem tartalmaz szöveget." : m.text)
                                .font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            if !m.attachments.isEmpty {
                                Divider()
                                ForEach(m.attachments, id: \.self) { name in
                                    Button { model.openSchoolWebsite() } label: {
                                        Label("\(name) · KRÉTA megnyitása", systemImage: "paperclip")
                                    }
                                    .buttonStyle(.glassy)
                                }
                                Text("A mellékleteket a hivatalos KRÉTA felületén töltheted le.").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .overlay(alignment: .topTrailing) { if loading { ProgressView().controlSize(.small) } }
                        .transition(.opacity)
                        .id(m.id)
                    } else {
                        EmptyState(title: "Válassz egy üzenetet", text: "A tartalma itt jelenik meg.")
                            .frame(minHeight: 280)
                    }
                }
            }
        }
        .onChange(of: folder) { selectedID = nil; detail = nil }
    }

    private func open(_ m: Message) {
        withAnimation(.smooth) { selectedID = m.id; detail = m }
        loading = true
        Task {
            if let full = await model.messageDetail(m.id), selectedID == m.id {
                withAnimation(.smooth) { detail = full }
            }
            loading = false
        }
    }
}

struct MessageRow: View {
    var message: Message
    var selected: Bool
    var action: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(message.read ? .clear : Color.accentColor).frame(width: 8, height: 8).padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(message.sender.isEmpty ? "—" : message.sender).font(.callout.weight(message.read ? .regular : .semibold)).lineLimit(1)
                        Spacer()
                        Text(Format.day(message.day)).font(.mono(11)).foregroundStyle(.secondary)
                    }
                    Text(message.subject).font(.callout.weight(.medium)).lineLimit(1)
                    Text(message.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(10)
            .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Notes

struct NotesPage: View {
    @Environment(AppModel.self) private var model
    @State private var filter = 0 // 0 all, 1 notes, 2 notices
    @State private var query = ""

    var body: some View {
        let q = query.searchKey
        let items = model.diary.notes.filter {
            (filter == 0 || (filter == 2) == ($0.tone == .notice)) && (q.isEmpty || "\($0.title) \($0.text) \($0.author)".searchKey.contains(q))
        }
        PageScaffold(eyebrow: "Feljegyzések és faliújság", title: "Feljegyzések") {
            GlassSearchField(prompt: "Keresés", text: $query)
        } content: {
            Picker("Forrás", selection: $filter) {
                Text("Mind").tag(0); Text("Feljegyzések").tag(1); Text("Faliújság").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            if items.isEmpty { Card { EmptyState(title: "Nincs megjeleníthető bejegyzés.") } }
            LazyVStack(spacing: 8) {
                ForEach(items) { NoteRow(note: $0) }
            }
        }
    }
}

struct NoteRow: View {
    var note: Note
    @State private var expanded = false

    private var tone: Color {
        switch note.tone {
        case .praise: .green
        case .warning: .red
        case .deficit: .orange
        case .notice: .blue
        case .neutral: .secondary
        }
    }

    var body: some View {
        let long = note.text.count > 220 || note.text.filter { $0 == "\n" }.count > 3
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(Format.day(note.date, year: true)).font(.mono(11)).foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(note.title).font(.body.weight(.semibold))
                HStack(spacing: 8) {
                    Pill(text: note.type.lowercased(), color: tone)
                    Text(note.author).font(.mono(11)).foregroundStyle(.secondary)
                }
                if !note.text.isEmpty {
                    Text(note.text)
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(expanded ? nil : 3)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                    if long {
                        Button(expanded ? "Kevesebb" : "Tovább") { expanded.toggle() }
                            .buttonStyle(.plain).font(.mono(11, .medium)).foregroundStyle(.tint)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .panel(radius: 12)
    }
}

// MARK: Consultations

struct ConsultationsPage: View {
    @Environment(AppModel.self) private var model
    @State private var detail: Consultation?

    var body: some View {
        PageScaffold(eyebrow: "Egy kis személyes figyelem", title: "Fogadóórák") {
            Button { model.openSchoolWebsite() } label: { Label("Hivatalos KRÉTA", systemImage: "safari") }.buttonStyle(.glassy)
        } content: {
            if model.diary.consultations.isEmpty {
                Card { EmptyState(title: "Jelenleg nincs elérhető fogadóóra.") }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                ForEach(model.diary.consultations) { c in
                    Card {
                        HStack(spacing: 12) {
                            Avatar(name: c.teacher, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.teacher.isEmpty ? "Tanári fogadóóra" : c.teacher).font(.headline)
                                Text(c.subject.isEmpty ? "Fogadóóra" : c.subject).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Label("\(Format.day(Day.of(c.start), year: true)) · \(Format.time(c.start))\(c.end.isEmpty ? "" : "–\(Format.time(c.end))")", systemImage: "clock")
                            .font(.callout)
                        if !c.room.isEmpty { Label(c.room, systemImage: "mappin.and.ellipse").font(.callout).foregroundStyle(.secondary) }
                        HStack {
                            if let b = c.booked { Pill(text: "Lefoglalva · \(b)", color: .green) }
                            Spacer()
                            Button("Részletek") { detail = c }.buttonStyle(.glassy)
                        }
                    }
                }
            }
        }
        .sheet(item: $detail) { ConsultationDetail(consultation: $0) }
    }
}

struct ConsultationDetail: View {
    var consultation: Consultation
    @Environment(AppModel.self) private var model
    @State private var full: JSON?

    var body: some View {
        let raw = full ?? consultation.raw
        let slots = raw["Idopontok"].rows
        DetailSheet(title: consultation.teacher.isEmpty ? "Fogadóóra" : consultation.teacher, subtitle: "Fogadóóra részletei") {
            InfoGrid(rows: [
                ("Időpont", "\(Format.day(Day.of(consultation.start), year: true)) · \(Format.time(consultation.start))"),
                ("Terem", raw["Terem"].name.isEmpty ? consultation.room : raw["Terem"].name),
            ])
            if !slots.isEmpty {
                Text("Idősávok").font(.headline)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(slots.enumerated()), id: \.offset) { _, s in
                            HStack {
                                Text("\(Format.time(s["KezdoIdopont"].text))–\(Format.time(s["VegIdopont"].text))").monospacedDigit()
                                Spacer()
                                if s["IsJelentkeztem"].bool == true { Pill(text: "Saját foglalás", color: .green) }
                                else if s["IsSzabad"].bool == false { Pill(text: "Foglalt", color: .secondary) }
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
            Text("Időpontot a hivatalos KRÉTA felületén foglalhatsz.").font(.caption).foregroundStyle(.secondary)
            Button { model.openSchoolWebsite() } label: { Label("KRÉTA megnyitása", systemImage: "safari") }.buttonStyle(.borderedProminent)
        }
        .task {
            if !consultation.id.isEmpty, let f = await model.consultingHour(consultation.id) { withAnimation(.smooth) { full = f } }
        }
    }
}

// MARK: LEP

struct LepPage: View {
    @Environment(AppModel.self) private var model
    @State private var confirm: (event: LepEvent, allow: Bool)?
    @State private var pending: String?

    var body: some View {
        PageScaffold(eyebrow: "Lázár Ervin Program", title: "Élmények az iskolán túl.",
                     subtitle: "Előadások, közös programok és részvételi engedélyek.") {
            if model.diary.lep.isEmpty { Card { EmptyState(title: "Nincsenek elérhető LEP események.") } }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                ForEach(model.diary.lep) { e in
                    Card {
                        Text(Format.day(e.date, year: true).uppercased()).font(.mono(11)).foregroundStyle(.tint)
                        Text(e.title).font(.title3.bold())
                        Label(e.place + (e.duration.map { " · \($0) perc" } ?? ""), systemImage: "mappin.and.ellipse")
                            .font(.callout).foregroundStyle(.secondary)
                        if !e.description.isEmpty { Text(e.description).font(.callout).lineLimit(5) }
                        HStack {
                            Pill(text: e.permitted ? "Engedélyezve" : "Nincs engedélyezve", color: e.permitted ? .green : .secondary)
                            Spacer()
                            if e.canDecide {
                                if pending == e.id { ProgressView().controlSize(.small) }
                                Button("Elutasítás") { confirm = (e, false) }.buttonStyle(.glassy)
                                Button("Engedélyezés") { confirm = (e, true) }.buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Részvételi engedély", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            if let c = confirm {
                Button(c.allow ? "Engedélyezem" : "Elutasítom", role: c.allow ? nil : .destructive) {
                    pending = c.event.id
                    Task { await model.lep(c.event, permit: c.allow); pending = nil }
                }
            }
        } message: {
            if let c = confirm { Text("\(c.allow ? "Engedélyezed" : "Elutasítod") a részvételt: \(c.event.title)") }
        }
    }
}
