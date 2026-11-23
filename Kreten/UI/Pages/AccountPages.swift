import SwiftUI

// MARK: Profile

struct ProfilePage: View {
    @Environment(AppModel.self) private var model
    @State private var editContact = false
    @State private var editBank = false
    @State private var confirmDeleteBank = false

    var body: some View {
        let s = model.diary.student
        let account = model.snapshot.activeAccount
        let bank = s["Bankszamla"]
        let name = s["Nev"].text.isEmpty ? (account?.name ?? "") : s["Nev"].text

        PageScaffold(eyebrow: "A te fiókod", title: "Profilom", subtitle: "Iskolai adatok és elérhetőségek, a KRÉTA rendszeréből.") {
            Button { model.beginLogin() } label: { Label("Fiók hozzáadása", systemImage: "person.badge.plus") }
                .buttonStyle(.glassy).controlSize(.large)
        } content: {
            Card(padding: 20) {
                HStack(spacing: 18) {
                    Avatar(name: name, size: 68)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.title.bold())
                        Text(s["IntezmenyNev"].text.isEmpty ? (account?.institutionName ?? "") : s["IntezmenyNev"].text).foregroundStyle(.secondary)
                        Pill(text: s["Osztaly"].text.isEmpty ? "Tanulói profil" : s["Osztaly"].text, color: Color.accentColor)
                    }
                }
            }
            AdaptiveColumns(trailingWidth: 380) {
                Card {
                    CardHeader("Személyes adatok")
                    InfoGrid(rows: [
                        ("Név", name),
                        ("Intézmény", s["IntezmenyNev"].text.isEmpty ? (account?.institutionName ?? "") : s["IntezmenyNev"].text),
                        ("Intézménykód", s["IntezmenyAzonosito"].text.isEmpty ? (account?.institutionCode ?? "") : s["IntezmenyAzonosito"].text),
                        ("Születési dátum", birthDate(s)),
                        ("Lakcím", (s["Cimek"].array ?? []).map(\.text).joined(separator: "; ")),
                        ("Oktatási azonosító", s["OktatasiAzonosito", "Uid"].text),
                    ])
                }
                Card {
                    CardHeader("Gondviselők")
                    let guardians = s["Gondviselok"].rows
                    if guardians.isEmpty { Text("Nincs megjeleníthető gondviselői adat.").font(.callout).foregroundStyle(.secondary) }
                    ForEach(Array(guardians.enumerated()), id: \.offset) { _, g in
                        HStack(spacing: 10) {
                            Avatar(name: g["Nev"].text, size: 30)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(g["Nev"].text).font(.callout.weight(.semibold))
                                Text(g["EmailCim"].text.isEmpty ? g["Telefonszam"].text : g["EmailCim"].text).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } trailing: {
                Card {
                    CardHeader(title: "Elérhetőségek") { LinkButton(title: "Szerkesztés") { editContact = true } }
                    InfoGrid(rows: [("E-mail", s["EmailCim"].text.isEmpty ? "Nincs megadva" : s["EmailCim"].text),
                                    ("Telefonszám", s["Telefonszam"].text.isEmpty ? "Nincs megadva" : s["Telefonszam"].text)])
                }
                Card {
                    CardHeader(title: "Bankszámlaadatok") {
                        if bank["IsReadOnly"].bool != true { LinkButton(title: "Szerkesztés") { editBank = true } }
                    }
                    InfoGrid(rows: [("Számlatulajdonos", bank["BankszamlaTulajdonosNeve"].text.isEmpty ? "Nincs megadva" : bank["BankszamlaTulajdonosNeve"].text),
                                    ("Számlaszám", bank["BankszamlaSzam"].text.isEmpty ? "Nincs megadva" : bank["BankszamlaSzam"].text)])
                    if bank["IsReadOnly"].bool == true {
                        Text("Az iskola nem engedi a módosítást.").font(.caption).foregroundStyle(.secondary)
                    } else if !bank["BankszamlaSzam"].text.isEmpty {
                        Button("Bankszámlaadatok törlése", role: .destructive) { confirmDeleteBank = true }.buttonStyle(.glassy)
                    }
                }
                Card {
                    CardHeader("Hozzáadott fiókok", count: model.snapshot.accounts.count)
                    ForEach(model.snapshot.accounts) { a in
                        HStack(spacing: 10) {
                            Avatar(name: a.name, size: 30)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(a.name).font(.callout.weight(.semibold))
                                Text(a.institutionName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if a.id == model.snapshot.activeAccountID { Pill(text: "Aktív", color: .green) }
                            else { Button("Váltás") { model.select(a) }.buttonStyle(.glassy).controlSize(.small) }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $editContact) { ContactEditor(email: s["EmailCim"].text, phone: s["Telefonszam"].text) }
        .sheet(isPresented: $editBank) {
            BankEditor(form: BankAccountUpdate(accountNumber: bank["BankszamlaSzam"].text, ownerName: bank["BankszamlaTulajdonosNeve"].text,
                                               ownerTypeID: Int(bank["BankszamlaTulajdonosTipusId"].number ?? 1), bankName: bank["SzamlavezetoBank"].text))
        }
        .confirmationDialog("Eltávolítod a bankszámlaadatokat a KRÉTA rendszeréből?", isPresented: $confirmDeleteBank) {
            Button("Adatok törlése", role: .destructive) { Task { await model.deleteBank() } }
        }
    }

    private func birthDate(_ s: JSON) -> String {
        if !s["SzuletesiDatum"].isNull { return Format.day(Day.of(s["SzuletesiDatum"]), year: true) }
        if !s["SzuletesiEv"].isNull { return "\(s["SzuletesiEv"].text). \(s["SzuletesiHonap"].text). \(s["SzuletesiNap"].text)." }
        return ""
    }
}

struct ContactEditor: View {
    @State var email: String
    @State var phone: String
    @State private var busy = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DetailSheet(title: "Elérhetőségek szerkesztése", subtitle: "A mentés frissíti a KRÉTA-ban tárolt elérhetőségeidet.") {
            Form {
                TextField("E-mail", text: $email).textContentType(.emailAddress)
                TextField("Telefonszám", text: $phone).textContentType(.telephoneNumber)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Mégse") { dismiss() }.buttonStyle(.glassy)
                Button(busy ? "Mentés…" : "Mentés a KRÉTA-ba") {
                    busy = true
                    Task { if await model.updateContact(email: email, phone: phone) { dismiss() }; busy = false }
                }
                .buttonStyle(.borderedProminent).disabled(busy).keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct BankEditor: View {
    @State var form: BankAccountUpdate
    @State private var busy = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DetailSheet(title: "Bankszámlaadatok szerkesztése", subtitle: "A mentés frissíti a KRÉTA-ban tárolt adatokat.") {
            Form {
                TextField("Számlaszám", text: $form.accountNumber)
                TextField("Tulajdonos neve", text: $form.ownerName)
                Picker("Tulajdonos", selection: $form.ownerTypeID) { Text("Szülő").tag(1); Text("Tanuló").tag(2) }
                TextField("Bank neve", text: $form.bankName)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Mégse") { dismiss() }.buttonStyle(.glassy)
                Button(busy ? "Mentés…" : "Mentés a KRÉTA-ba") {
                    busy = true
                    Task { if await model.updateBank(form) { dismiss() }; busy = false }
                }
                .buttonStyle(.borderedProminent).disabled(busy).keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: Notifications

struct NotificationsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.snapshot.notifications
        PageScaffold(eyebrow: "Amiről érdemes tudnod", title: "Értesítések",
                     subtitle: "A háttérfrissítés által észlelt legutóbbi változások.") {
            if !items.isEmpty {
                Button("Összes törlése", systemImage: "trash") { model.dismiss(nil) }.buttonStyle(.glassy)
            }
        } content: {
            if items.isEmpty {
                Card { EmptyState(title: "Minden frissítéssel képben vagy.", text: "Az új jegyek, órarendváltozások és üzenetek itt jelennek meg.") }
            }
            LazyVStack(spacing: 10) {
                ForEach(items) { n in
                    NotificationRow(notification: n)
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
        }
    }
}

struct NotificationRow: View {
    var notification: AppNotification
    @Environment(AppModel.self) private var model
    @State private var hover = false

    var body: some View {
        let page = Page(rawValue: notification.kind == "messagesInbox" ? "messages" : notification.kind == "tests" ? "homework" : notification.kind)
        let category = NotificationCategory(rawValue: notification.kind)
        Card(padding: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.title).font(.callout.weight(.semibold))
                    Text(notification.body).font(.callout).foregroundStyle(.secondary)
                    Text("\(category?.label.lowercased() ?? "") · \(Format.relative(notification.createdAt))").font(.mono(11)).foregroundStyle(.tertiary)
                }
                Spacer()
                if let page {
                    Button("Megnyitás") { model.page = page }.buttonStyle(.glassy).controlSize(.small)
                }
                Button { model.dismiss(notification) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.glassy).buttonBorderShape(.circle).controlSize(.small)
                    .opacity(hover ? 1 : 0.4)
                    .help("Értesítés elvetése")
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}
