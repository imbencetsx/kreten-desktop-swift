import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // List selection is optional; ignore deselection.
        let selection = Binding<Page?>(get: { model.page }, set: { if let p = $0 { model.page = p } })
        List(selection: selection) {
            section("Napló", Page.diary)
            section("Iskolai élet", Page.school)
            section("Fiók", Page.account)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Image("Logo")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(height: 22)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AccountSwitcher().padding(10)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ pages: [Page]) -> some View {
        let visible = pages.filter { $0 == .dashboard || !model.prefs.hiddenPages.contains($0) }
        if !visible.isEmpty {
            Section(title) {
                ForEach(visible) { page in
                    Label(page.label, systemImage: page.icon)
                        .badge(badge(for: page))
                        .tag(page)
                }
            }
        }
    }

    private func badge(for page: Page) -> Int {
        switch page {
        case .homework:
            model.diary.homework.filter { !model.isDone($0) && ($0.date.isEmpty || $0.date >= Day.today) }.count
        case .tests:
            model.diary.tests.filter { $0.date.isEmpty || $0.date >= Day.today }.count
        case .messages:
            (model.diary.messages[.messagesInbox] ?? []).filter { !$0.read }.count
        case .notifications:
            model.snapshot.notifications.count
        default: 0
        }
    }
}

struct AccountSwitcher: View {
    @Environment(AppModel.self) private var model
    @State private var confirmLogout: Account?

    var body: some View {
        let account = model.snapshot.activeAccount
        Menu {
            Section("Fiókok") {
                ForEach(model.snapshot.accounts) { a in
                    Button {
                        model.select(a)
                    } label: {
                        if a.id == account?.id { Label(a.name, systemImage: "checkmark") } else { Text(a.name) }
                    }
                }
            }
            Divider()
            Button("Fiók hozzáadása…", systemImage: "plus") { model.beginLogin() }
            Button("Profilom", systemImage: "person.crop.circle") { model.page = .profile }
            Button("Hivatalos KRÉTA megnyitása", systemImage: "safari") { model.openSchoolWebsite() }
            Divider()
            if model.isDemo {
                Button("Kilépés a bemutatóból", systemImage: "xmark.circle") { model.exitDemo() }
            } else if let account {
                Button("Kijelentkezés", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmLogout = account
                }
            }
        } label: {
            HStack(spacing: 10) {
                Avatar(name: account?.name ?? "?", size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account?.name ?? "").font(.callout.weight(.semibold)).lineLimit(1)
                    Text(account?.institutionName ?? "").font(.mono(10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .contentShape(.rect(cornerRadius: 16))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .confirmationDialog("Kijelentkezel?", isPresented: Binding(get: { confirmLogout != nil }, set: { if !$0 { confirmLogout = nil } }),
                            presenting: confirmLogout) { a in
            Button("Kijelentkezés", role: .destructive) { model.logout(a) }
        } message: { a in
            Text("\(a.name) helyi adatai és munkamenete törlődnek erről a Macről.")
        }
    }
}

struct Avatar: View {
    var name: String
    var size: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        Text(initials.isEmpty ? "K" : initials)
            .font(.system(size: size * 0.4, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            // Contacts-style monogram.
            .background(LinearGradient(colors: [Color(white: 0.64), Color(white: 0.46)], startPoint: .top, endPoint: .bottom), in: .circle)
    }
}
