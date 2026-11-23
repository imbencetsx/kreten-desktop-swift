import SwiftUI

@main
struct KretenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("KRETÉN", id: "main") {
            RootView()
                .environment(model)
                .environment(\.reducedEffects, model.reducedEffects)
                .tint(model.prefs.palette.tint)
                .preferredColorScheme(model.prefs.theme.colorScheme)
                .fontDesign(.default)
        }
        .defaultSize(width: 1240, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: "startMinimized") ? .suppressed : .presented)
        .commands { AppCommands(model: model) }

        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
                .environment(\.reducedEffects, model.reducedEffects)
                .tint(model.prefs.palette.tint)
                .preferredColorScheme(model.prefs.theme.colorScheme)
        } label: {
            Image(systemName: model.syncing ? "arrow.triangle.2.circlepath" : "graduationcap.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(\.reducedEffects, model.reducedEffects)
                .tint(model.prefs.palette.tint)
                .preferredColorScheme(model.prefs.theme.colorScheme)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the window keeps KRETÉN syncing from the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct AppCommands: Commands {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Frissítés most") { Task { await model.refresh() } }
                .keyboardShortcut("r")
                .disabled(!model.hasAccount || model.syncing)
            Button("Fiók hozzáadása…") { openWindow(id: "main"); model.beginLogin() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("Napló") {
            ForEach(Array((Page.diary + Page.school + Page.account).enumerated()), id: \.element) { i, page in
                Button(page.label) { openWindow(id: "main"); model.page = page }
                    .keyboardShortcut(i < 9 ? KeyboardShortcut(KeyEquivalent(Character("\(i + 1)"))) : nil)
            }
        }
    }
}
