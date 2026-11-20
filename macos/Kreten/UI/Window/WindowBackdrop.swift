import AppKit
import SwiftUI

/// Window-server background blur. Private SkyLight API (the same one terminal
/// emulators use for "background blur"), resolved at runtime so a missing
/// symbol just disables blur instead of crashing.
enum WindowBlur {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetRadius = @convention(c) (Int32, UInt32, Int32) -> Int32

    nonisolated(unsafe) private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    private static let connection: MainConnection? =
        dlsym(rtldDefault, "CGSMainConnectionID").map { unsafeBitCast($0, to: MainConnection.self) }
    private static let setRadius: SetRadius? =
        dlsym(rtldDefault, "CGSSetWindowBackgroundBlurRadius").map { unsafeBitCast($0, to: SetRadius.self) }

    static var isAvailable: Bool { connection != nil && setRadius != nil }

    @MainActor static func apply(_ window: NSWindow, radius: Int) {
        guard let connection, let setRadius, window.windowNumber > 0 else { return }
        _ = setRadius(connection(), UInt32(window.windowNumber), Int32(max(0, min(100, radius))))
    }
}

/// Reads `WindowLook` itself so only this view (not the whole tree) updates while a slider moves.
struct WindowConfigurator: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        WindowAccessor(backdrop: model.look.backdrop, blur: Int(model.look.blur.rounded()))
            .frame(width: 0, height: 0)
    }
}

/// Makes the hosting NSWindow non-opaque and applies the blur radius.
/// The tint itself is drawn by SwiftUI as the window's container background.
struct WindowAccessor: NSViewRepresentable {
    var backdrop: WindowBackdrop
    var blur: Int

    final class Probe: NSView {
        var onWindow: ((NSWindow) -> Void)?
        var applied: (WindowBackdrop, Int)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applied = nil
            if let window { onWindow?(window) }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onWindow = { [weak probe] window in
            // The window number is assigned after ordering in; retry next runloop turn.
            DispatchQueue.main.async { probe.map { configure(window, probe: $0) } }
        }
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.onWindow = { [weak probe] window in probe.map { configure(window, probe: $0) } }
        if let window = probe.window { configure(window, probe: probe) }
    }

    private func configure(_ window: NSWindow, probe: Probe) {
        // Only touch the window server when something actually changed.
        if let applied = probe.applied, applied.0 == backdrop, applied.1 == blur { return }
        let clear = backdrop != .gradient
        if window.isOpaque == clear { window.isOpaque = !clear }
        let background: NSColor = clear ? .clear : .windowBackgroundColor
        if window.backgroundColor != background { window.backgroundColor = background }
        window.titlebarAppearsTransparent = true
        WindowBlur.apply(window, radius: backdrop == .translucent ? blur : 0)
        if window.windowNumber > 0 { probe.applied = (backdrop, blur) }
    }
}

/// The window's base layer: tinted see-through glass, system material, or a gradient wallpaper.
struct BackdropView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let look = model.look
        switch look.backdrop {
        case .translucent:
            tint.opacity(look.opacity)
        case .glass:
            Rectangle().fill(.regularMaterial)
        case .gradient:
            GradientWallpaper(a: Color(hexString: look.gradientColor1), b: Color(hexString: look.gradientColor2), animated: look.animatedGradient)
                .overlay(scheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.25))
        }
    }

    private var tint: Color {
        if model.look.tintWithAccent {
            return model.accent.mix(with: scheme == .dark ? .black : .white, by: scheme == .dark ? 0.75 : 0.8)
        }
        // Neutral, slightly warm grays (close to Finder/Terminal translucency).
        return scheme == .dark ? Color(hex: 0x1C1C1E) : Color(hex: 0xF2F2F4)
    }
}

struct GradientWallpaper: View {
    var a: Color
    var b: Color
    var animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !animated || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let s = Float(sin(t / 7)) * 0.18, c = Float(cos(t / 9)) * 0.18
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + s, 0.5 + c], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                a, a.mix(with: b, by: 0.5), b,
                a.mix(with: b, by: 0.3), a.mix(with: b, by: 0.5), b.mix(with: a, by: 0.3),
                b, b.mix(with: a, by: 0.5), a,
            ])
        }
    }
}
