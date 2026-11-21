import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let error = model.startupError {
                StartupErrorView(message: error)
            } else if !model.loaded {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.hasAccount {
                WelcomeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                MainSplitView()
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 940, minHeight: 620)
        .animation(.smooth(duration: 0.35), value: model.hasAccount)
        .background(WindowConfigurator())
        .containerBackground(for: .window) { BackdropView().environment(model) }
        .sheet(item: $model.login) { session in
            LoginSheet(session: session)
        }
        .overlay(alignment: .bottom) { ToastOverlay() }
    }
}

struct MainSplitView: View {
    @Environment(AppModel.self) private var model
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 300)
        } detail: {
            PageHost()
                .toolbar { MainToolbar() }
                .navigationTitle(model.page.label)
                .toolbarTitleDisplayMode(.inline)
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

/// Swaps pages with a short cross-fade (native apps switch near-instantly;
/// a long animated transition of a whole page reads as lag).
struct PageHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            page(model.page)
                .id(model.page)
                .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.14), value: model.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func page(_ p: Page) -> some View {
        switch p {
        case .dashboard: DashboardPage()
        case .timetable: TimetablePage()
        case .grades: GradesPage()
        case .statistics: StatisticsPage()
        case .progress: SchoolProgressPage()
        case .homework: HomeworkPage()
        case .tests: TestsPage()
        case .absences: AbsencesPage()
        case .messages: MessagesPage()
        case .notes: NotesPage()
        case .consultations: ConsultationsPage()
        case .lep: LepPage()
        case .profile: ProfilePage()
        case .notifications: NotificationsPage()
        }
    }
}

struct MainToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            SyncStatus()
        }
        if model.isDemo {
            ToolbarItem(placement: .primaryAction) {
                Button { model.exitDemo() } label: {
                    Label("Bemutató · kilépés", systemImage: "xmark.circle")
                        .labelStyle(.titleAndIcon)
                }
                .tint(.orange)
                .help("Mintaadatokat látsz. Kattints a kilépéshez.")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.prefs.privateGrades {
                Button {
                    model.gradesHidden ? model.revealGrades() : model.hideGrades()
                } label: {
                    Label(model.gradesHidden ? "Jegyek felfedése" : "Jegyek elrejtése",
                          systemImage: model.gradesHidden ? "eye.slash" : "eye")
                        .contentTransition(.symbolEffect(.replace))
                }
                .help(model.gradesHidden ? "Jegyek felfedése" : "Jegyek elrejtése")
            }
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Frissítés", systemImage: "arrow.clockwise")
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: model.syncing)
            }
            .disabled(model.syncing)
            .help("Frissítés most (⌘R)")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.page = .notifications
            } label: {
                Label("Értesítések", systemImage: model.snapshot.notifications.isEmpty ? "bell" : "bell.badge")
                    .symbolRenderingMode(.multicolor)
            }
            .help("Értesítések")
        }
    }
}

struct SyncStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.snapshot
        HStack(spacing: 6) {
            if model.syncing {
                ProgressView().controlSize(.mini)
                Text("Szinkronizálás…")
            } else if s.offline && s.lastSyncedAt != nil {
                Image(systemName: "wifi.slash").foregroundStyle(.orange)
                Text("Offline · mentett adatok")
            } else if !s.errors.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("\(s.errors.count) forrás nem frissült")
            } else if let last = s.lastSyncedAt {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text("Frissítve \(Format.relative(last))")
                }
            }
        }
        .font(.mono(12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .help(s.errors.map { "\(syncLabel($0.key)): \($0.value)" }.sorted().joined(separator: "\n"))
        .animation(.smooth, value: model.syncing)
    }
}

func syncLabel(_ key: String) -> String {
    [
        "student": "Profil", "grades": "Jegyek", "timetable": "Órarend", "homework": "Házi feladatok",
        "tests": "Dolgozatok", "absences": "Hiányzások", "notices": "Faliújság", "notes": "Feljegyzések",
        "groups": "Osztályok", "classAverages": "Osztályátlagok", "schoolYear": "Tanév rendje",
        "consultations": "Fogadóórák", "lep": "LEP", "guardian": "Gondviselő", "capabilities": "Intézmény",
        "dktSubjects": "Digitális tantárgyak", "messagesInbox": "Beérkezett", "messagesSent": "Elküldött",
        "messagesDeleted": "Törölt", "connection": "Kapcsolat",
    ][key] ?? key
}

struct ToastOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            Label(toast.text, systemImage: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular.tint(toast.isError ? .red.opacity(0.25) : nil), in: .capsule)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                .id(toast.id)
                .onTapGesture { withAnimation(.smooth) { model.toast = nil } }
        }
    }
}

struct StartupErrorView: View {
    var message: String
    var body: some View {
        ContentUnavailableView {
            Label("A KRETÉN nem tudott elindulni", systemImage: "lock.trianglebadge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Kilépés") { NSApp.terminate(nil) }.buttonStyle(.glass)
        }
    }
}
