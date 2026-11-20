import SwiftUI

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var label: String { switch self { case .system: "Rendszer"; case .light: "Világos"; case .dark: "Sötét" } }
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

/// Accent color. `system` follows System Settings → Appearance → Accent color.
enum Palette: String, Codable, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite
    var id: Self { self }
    var label: String {
        switch self {
        case .system: "Rendszer"; case .blue: "Kék"; case .purple: "Lila"; case .pink: "Rózsaszín"
        case .red: "Piros"; case .orange: "Narancs"; case .yellow: "Sárga"; case .green: "Zöld"; case .graphite: "Grafit"
        }
    }
    /// Apple's dynamic system colors, so contrast is handled per appearance.
    var color: Color {
        switch self {
        case .system: .accentColor
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .graphite: .gray
        }
    }
    /// `nil` leaves the system accent untouched.
    var tint: Color? { self == .system ? nil : color }
}

enum WindowBackdrop: String, Codable, CaseIterable, Identifiable {
    /// Desktop shows through, blurred and tinted (adjustable).
    case translucent
    /// System Liquid Glass window material.
    case glass
    /// Soft two-color gradient wallpaper.
    case gradient
    var id: Self { self }
    var label: String { switch self { case .translucent: "Átlátszó"; case .glass: "Üveg"; case .gradient: "Színátmenet" } }
}

enum TitleFont: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif
    var id: Self { self }
    var label: String { switch self { case .system: "Rendszer"; case .rounded: "Lekerekített"; case .serif: "Talpas" } }
    var design: Font.Design { switch self { case .system: .default; case .rounded: .rounded; case .serif: .serif } }
}

enum Page: String, Codable, CaseIterable, Identifiable, Hashable {
    case dashboard, timetable, grades, statistics, progress, homework, tests, absences
    case messages, notes, consultations, lep, profile, notifications
    var id: Self { self }

    var label: String {
        switch self {
        case .dashboard: "Áttekintés"; case .timetable: "Órarend"; case .grades: "Jegyek"
        case .statistics: "Statisztikák"; case .progress: "Haladás"; case .homework: "Házi feladatok"
        case .tests: "Dolgozatok"; case .absences: "Hiányzások"; case .messages: "Üzenetek"; case .notes: "Feljegyzések"
        case .consultations: "Fogadóórák"; case .lep: "LEP programok"; case .profile: "Profilom"
        case .notifications: "Értesítések"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "house"; case .timetable: "calendar"; case .grades: "graduationcap"
        case .statistics: "chart.bar.xaxis"; case .progress: "hourglass"; case .homework: "book"
        case .tests: "pencil.and.outline"; case .absences: "clock.badge.xmark"; case .messages: "envelope"; case .notes: "doc.text"
        case .consultations: "person.2"; case .lep: "theatermasks"; case .profile: "person.crop.circle"
        case .notifications: "bell"
        }
    }

    static let diary: [Page] = [.dashboard, .timetable, .grades, .statistics, .progress, .homework, .tests, .absences]
    static let school: [Page] = [.messages, .notes, .consultations, .lep]
    static let account: [Page] = [.profile, .notifications]
}

/// User preferences. Stored in UserDefaults (not secret) so sliders can save freely.
struct Preferences: Codable, Equatable {
    var pollIntervalMinutes = 5
    var notificationsEnabled = true
    var startMinimized = false
    var launchAtLogin = false
    var theme = ThemeMode.system
    var palette = Palette.system
    var privateGrades = false
    var bellOffsetMinutes = 0
    var mutedSubjects: [String] = []
    var notificationCategories: Set<NotificationCategory> = Set(NotificationCategory.allCases)
    var titleFont = TitleFont.rounded
    var gradeThresholds: [Double] = [1.5, 2.5, 3.5, 4.5]
    var hiddenPages: Set<Page> = []

    init() {}

    // Tolerant decoding so new fields never wipe existing preferences.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ into: inout T) { if let x = try? c.decode(T.self, forKey: k) { into = x } }
        v(.pollIntervalMinutes, &pollIntervalMinutes); v(.notificationsEnabled, &notificationsEnabled)
        v(.startMinimized, &startMinimized); v(.launchAtLogin, &launchAtLogin); v(.theme, &theme)
        v(.palette, &palette); v(.privateGrades, &privateGrades); v(.bellOffsetMinutes, &bellOffsetMinutes)
        v(.mutedSubjects, &mutedSubjects); v(.notificationCategories, &notificationCategories)
        v(.titleFont, &titleFont); v(.gradeThresholds, &gradeThresholds); v(.hiddenPages, &hiddenPages)
    }

    static let defaultsKey = "preferences.v1"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let p = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return p
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
    }

    var syncPreferences: SyncPreferences {
        SyncPreferences(categories: notificationCategories, mutedSubjects: Set(mutedSubjects), privateGrades: privateGrades)
    }
}

/// Window backdrop settings live apart from `Preferences`: dragging a slider must
/// only invalidate the backdrop, not every view that reads a preference.
@MainActor @Observable
final class WindowLook {
    var backdrop = WindowBackdrop.translucent { didSet { scheduleSave() } }
    /// 0 = fully see-through tint, 1 = opaque.
    var opacity = 0.55 { didSet { scheduleSave() } }
    /// Window-server blur radius behind the window.
    var blur = 24.0 { didSet { scheduleSave() } }
    /// Tint the translucent window with the accent instead of neutral gray.
    var tintWithAccent = false { didSet { scheduleSave() } }
    var gradientColor1 = "#4f7fd9" { didSet { scheduleSave() } }
    var gradientColor2 = "#8a6fd1" { didSet { scheduleSave() } }
    var animatedGradient = true { didSet { scheduleSave() } }

    private struct Stored: Codable {
        var backdrop: WindowBackdrop?
        var windowOpacity: Double?
        var windowBlur: Double?
        var tintWithAccent: Bool?
        var gradientColor1: String?
        var gradientColor2: String?
        var animatedGradient: Bool?
    }

    private static let key = "windowLook.v1"
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var loading = true

    init() {
        // Falls back to the keys earlier builds kept inside `preferences.v1`.
        let data = UserDefaults.standard.data(forKey: Self.key) ?? UserDefaults.standard.data(forKey: Preferences.defaultsKey)
        if let data, let s = try? JSONDecoder().decode(Stored.self, from: data) {
            backdrop = s.backdrop ?? backdrop
            opacity = s.windowOpacity ?? opacity
            blur = s.windowBlur ?? blur
            tintWithAccent = s.tintWithAccent ?? tintWithAccent
            gradientColor1 = s.gradientColor1 ?? gradientColor1
            gradientColor2 = s.gradientColor2 ?? gradientColor2
            animatedGradient = s.animatedGradient ?? animatedGradient
        }
        loading = false
    }

    /// Debounced: a slider drag writes once, after it settles.
    private func scheduleSave() {
        guard !loading else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            let s = Stored(backdrop: backdrop, windowOpacity: opacity, windowBlur: blur, tintWithAccent: tintWithAccent,
                           gradientColor1: gradientColor1, gradientColor2: gradientColor2, animatedGradient: animatedGradient)
            if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.key) }
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    init(hexString: String) {
        let s = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(s, radix: 16) ?? 0x629EF2)
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#629ef2" }
        return String(format: "#%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
