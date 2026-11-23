import Observation
import ServiceManagement
import SwiftUI
import UserNotifications

/// Parsed, render-ready view of the active account's cache. Rebuilt once per snapshot.
struct DiaryData {
    var grades: [Grade] = []
    var lessons: [Lesson] = []
    var homework: [Homework] = []
    var tests: [AnnouncedTest] = []
    var absences: [Absence] = []
    var notes: [Note] = []
    var consultations: [Consultation] = []
    var lep: [LepEvent] = []
    var classAverages: [ClassAverage] = []
    var schoolYear: [SchoolYearEvent] = []
    var calendar = SchoolCalendar(.null)
    var messages: [MessageFolder: [Message]] = [:]
    var student: JSON = .null
    // Derived once per snapshot instead of on every render.
    var timeline: LiveStatus.Timeline = []
    var gradeAverage: Double?
    var subjectCount = 0

    init() {}
    init(_ s: Snapshot) {
        grades = Grade.parse(s["grades"])
        gradeAverage = grades.average
        subjectCount = Set(grades.map(\.subject)).count
        lessons = Lesson.parse(s["timetable"])
        timeline = LiveStatus.timeline(lessons)
        homework = Homework.parse(s["homework"])
        tests = AnnouncedTest.parse(s["tests"])
        absences = Absence.parse(s["absences"])
        notes = Note.parse(notes: s["notes"], notices: s["notices"])
        consultations = Consultation.parse(s["consultations"])
        lep = LepEvent.parse(s["lep"])
        classAverages = ClassAverage.parse(s["classAverages"])
        schoolYear = SchoolYearEvent.parse(s["schoolYear"])
        calendar = SchoolCalendar(s["schoolYear"])
        for f in MessageFolder.allCases { messages[f] = Message.parse(s[f.rawValue]) }
        student = s["student"]
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var isError = false
}

@MainActor @Observable
final class AppModel {
    private(set) var core: KretaCore?
    private(set) var startupError: String?
    private(set) var snapshot = Snapshot()
    private(set) var diary = DiaryData()
    private(set) var syncing = false
    private(set) var loaded = false
    var paused = false { didSet { if !paused { requestRefresh() } } }
    /// Last visited page survives relaunches (also settable with `-page grades`).
    var page: Page = UserDefaults.standard.string(forKey: "page").flatMap(Page.init) ?? .dashboard {
        didSet { UserDefaults.standard.set(page.rawValue, forKey: "page") }
    }
    var toast: Toast?
    var login: LoginSession?

    var prefs = Preferences.load() {
        didSet {
            guard prefs != oldValue else { return }
            prefs.save()
            UserDefaults.standard.set(prefs.startMinimized, forKey: "startMinimized")
            if prefs.launchAtLogin != oldValue.launchAtLogin { applyLaunchAtLogin() }
            if prefs.pollIntervalMinutes != oldValue.pollIntervalMinutes { requestRefresh() }
        }
    }

    private var pollTask: Task<Void, Never>?
    private var refreshRequested = true
    private var toastTask: Task<Void, Never>?

    init() {
        do {
            let core = try KretaCore()
            self.core = core
            Task {
                let initial = await core.snapshot()
                if CommandLine.arguments.contains("-demo") { isDemo = true; apply(Demo.snapshot()) } else { apply(initial) }
                loaded = true
                startPolling()
            }
        } catch {
            startupError = error.localizedDescription
            loaded = true
        }
    }

    /// Session-only reveal of private grades.
    var gradesRevealed = false
    var gradesHidden: Bool { prefs.privateGrades && !gradesRevealed }
    func revealGrades() { withAnimation(.smooth) { gradesRevealed = true } }
    func hideGrades() { withAnimation(.smooth) { gradesRevealed = false } }

    var accent: Color { prefs.palette.color }
    /// Flat surfaces, opaque window, no decorative animation.
    var reducedEffects: Bool { prefs.effects.isReduced }
    /// False while the main window is closed, minimized or fully covered;
    /// clocks pause so nothing re-renders off screen.
    var windowVisible = true
    let look = WindowLook()
    var hasAccount: Bool { snapshot.activeAccountID != nil }

    // MARK: Demo

    /// Sample data that never touches KRÉTA or the encrypted store.
    private(set) var isDemo = false

    func startDemo() {
        withAnimation(.smooth) {
            isDemo = true
            apply(Demo.snapshot())
        }
    }

    func exitDemo() {
        guard isDemo else { return }
        Task {
            let s = await core?.snapshot() ?? Snapshot()
            withAnimation(.smooth) { isDemo = false; apply(s) }
        }
    }
    var firstName: String {
        let n = diary.student["Nev"].text.isEmpty ? (snapshot.activeAccount?.name ?? "") : diary.student["Nev"].text
        return n.split(separator: " ").last.map(String.init) ?? n
    }
    /// "Now" shifted by the configured bell offset, for lesson countdowns.
    func schoolNow(_ date: Date = Date()) -> Date { date.addingTimeInterval(TimeInterval(-prefs.bellOffsetMinutes * 60)) }

    private func apply(_ s: Snapshot) {
        snapshot = s
        diary = DiaryData(s)
        if let id = s.activeAccountID, !s.accounts.contains(where: { $0.id == id }) { page = .dashboard }
    }

    // MARK: Feedback

    func show(_ text: String, error: Bool = false) {
        withAnimation(.snappy) { toast = Toast(text: text, isError: error) }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { toast = nil }
        }
    }

    /// Runs a core operation, showing failures as a toast.
    @discardableResult
    func perform<T>(success: String? = nil, _ op: (KretaCore) async throws -> T) async -> T? {
        guard let core else { return nil }
        if isDemo {
            show("Bemutató módban nincs KRÉTA-kapcsolat.")
            return nil
        }
        do {
            let r = try await op(core)
            if let success { show(success) }
            return r
        } catch {
            show(error.localizedDescription, error: true)
            return nil
        }
    }

    // MARK: Sync

    func requestRefresh() { refreshRequested = true }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var last: ContinuousClock.Instant?
            while !Task.isCancelled {
                guard let self else { return }
                let interval = Duration.seconds(max(1, min(60, self.prefs.pollIntervalMinutes)) * 60)
                if !self.paused, self.hasAccount, self.refreshRequested || last.map({ $0.duration(to: .now) >= interval }) ?? true {
                    self.refreshRequested = false
                    await self.refresh()
                    last = .now
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func refresh() async {
        guard let core, !syncing, !isDemo else { return }
        withAnimation(.smooth) { syncing = true }
        let outcome = await core.refreshAll(prefs.syncPreferences)
        withAnimation(.smooth) {
            apply(outcome.snapshot)
            syncing = false
        }
        if prefs.notificationsEnabled { post(outcome.notifications) }
    }

    private func post(_ items: [AppNotification]) {
        guard !items.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        // Avoid a burst of banners after a long offline interval.
        for n in items.prefix(3) {
            let c = UNMutableNotificationContent()
            c.title = n.title
            c.body = n.body
            c.sound = .default
            center.add(UNNotificationRequest(identifier: n.id, content: c, trigger: nil))
        }
        if items.count > 3 {
            let c = UNMutableNotificationContent()
            c.title = "KRETÉN"
            c.body = "További \(items.count - 3) változás. Nyisd meg az alkalmazást a részletekért."
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }

    func requestNotificationPermission() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
    }

    func sendTestNotification() {
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let c = UNMutableNotificationContent()
            c.title = "Próbaértesítés"
            c.body = "Így fognak kinézni a KRETÉN értesítései."
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if prefs.launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            show("Az automatikus indítás beállítása sikertelen: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: Accounts

    func beginLogin() {
        guard let core else { return }
        exitDemo()
        Task {
            do {
                let attempt = try await core.beginLogin()
                login = LoginSession(id: attempt.id, url: attempt.url)
            } catch { show(error.localizedDescription, error: true) }
        }
    }

    func cancelLogin() {
        if let id = login?.id { Task { await core?.cancelLogin(id) } }
        login = nil
    }

    func completeLogin(_ redirect: URL) {
        guard let session = login else { return }
        login = nil
        Task {
            if let s = await perform({ try await $0.completeLogin(attempt: session.id, redirect: redirect) }) {
                withAnimation(.smooth) { apply(s); page = .dashboard }
                requestNotificationPermission()
                await refresh()
            }
        }
    }

    func select(_ account: Account) {
        Task {
            if let s = await perform({ try await $0.selectAccount(account.id) }) {
                withAnimation(.smooth) { apply(s) }
                await refresh()
            }
        }
    }

    func logout(_ account: Account) {
        Task {
            if let s = await perform(success: "Kijelentkeztél: \(account.name)", { try await $0.logout(account.id) }) {
                withAnimation(.smooth) { apply(s) }
            }
        }
    }

    // MARK: Local state

    func isDone(_ h: Homework) -> Bool { h.doneInKreta || snapshot.completedHomework.contains(h.id) }

    func toggleHomework(_ h: Homework) {
        let complete = !snapshot.completedHomework.contains(h.id)
        withAnimation(.snappy) {
            if complete { snapshot.completedHomework.insert(h.id) } else { snapshot.completedHomework.remove(h.id) }
        }
        Task {
            if let s = await perform({ try await $0.setHomework(h.id, complete: complete) }) { snapshot.completedHomework = s.completedHomework }
        }
    }

    func dismiss(_ n: AppNotification?) {
        withAnimation(.snappy) {
            if let n { snapshot.notifications.removeAll { $0.id == n.id } } else { snapshot.notifications.removeAll() }
        }
        Task { await perform { try await $0.dismissNotification(n?.id) } }
    }

    // MARK: Remote actions

    func timetable(weekOf monday: String) async -> [Lesson]? {
        guard let json = await perform({ try await $0.timetable(from: monday, to: Day.add(monday, 6)) }) else { return nil }
        return Lesson.parse(json)
    }

    func messageDetail(_ id: String) async -> Message? {
        guard let json = await perform({ try await $0.messageDetail(id) }) else { return nil }
        return Message.parse(.array([json])).first
    }

    func consultingHour(_ id: String) async -> JSON? { await perform { try await $0.consultingHour(id) } }

    func lep(_ event: LepEvent, permit: Bool) async {
        if await perform(success: "Döntés mentve.", { try await $0.lepPermission(eventID: event.id, permitted: permit) }) != nil {
            await refresh()
        }
    }

    func updateContact(email: String, phone: String) async -> Bool {
        let ok = await perform(success: "Elérhetőségek mentve.", { try await $0.updateContact(email: email, phone: phone) }) != nil
        if ok { await refresh() }
        return ok
    }

    func updateBank(_ bank: BankAccountUpdate) async -> Bool {
        let ok = await perform(success: "Bankszámlaadatok mentve.", { try await $0.updateBank(bank) }) != nil
        if ok { await refresh() }
        return ok
    }

    func deleteBank() async {
        if await perform(success: "Bankszámlaadatok törölve.", { try await $0.deleteBank() }) != nil { await refresh() }
    }

    func openSchoolWebsite() {
        guard let code = snapshot.activeAccount?.institutionCode,
              let valid = try? OAuth.validateInstitution(code),
              let url = URL(string: "https://\(valid).e-kreta.hu") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct LoginSession: Identifiable, Equatable {
    var id: String
    var url: URL
}
