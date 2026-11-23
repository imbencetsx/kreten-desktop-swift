import AppKit
import Metal
import SwiftUI

// MARK: Hardware

enum Hardware {
    /// Older Intel Macs (e.g. Ivy Bridge HD 4000) can't keep Liquid Glass, live
    /// window blur and full-window transparency at a usable frame rate.
    /// Apple silicon is always fast enough; on Intel, integrated GPUs and GPUs
    /// below Metal's Mac2 family get reduced effects by default.
    static let isLowEnd: Bool = {
        #if arch(arm64)
        return false
        #else
        guard let gpu = MTLCreateSystemDefaultDevice() else { return true }
        return gpu.isLowPower || !gpu.supportsFamily(.mac2)
        #endif
    }()
}

extension EnvironmentValues {
    /// Flat surfaces and no decorative animation (see `EffectsMode`).
    @Entry var reducedEffects = false
}

// MARK: Surfaces

/// Liquid Glass normally; a flat translucent fill when effects are reduced.
/// Each glass surface samples and blurs what's behind it, which is the main
/// rendering cost on weak GPUs.
struct Surface<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color?
    var interactive = false
    @Environment(\.reducedEffects) private var reduced

    func body(content: Content) -> some View {
        if reduced {
            content.background {
                shape.fill(Self.flatFill)
                    .overlay { if let tint { shape.fill(tint) } }
                    .overlay { shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }
            }
        } else {
            content.glassEffect(interactive ? .regular.tint(tint).interactive() : .regular.tint(tint), in: shape)
        }
    }

    static var flatFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.06)
                : NSColor(white: 1, alpha: 0.75)
        })
    }
}

extension View {
    func surface<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(Surface(shape: shape, tint: tint, interactive: interactive))
    }
}

/// `.glass` buttons, or standard bordered buttons when effects are reduced.
struct AdaptiveGlassButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View { GlassyButton(configuration: configuration) }

    private struct GlassyButton: View {
        let configuration: Configuration
        @Environment(\.reducedEffects) private var reduced
        var body: some View {
            if reduced { Button(configuration).buttonStyle(.bordered) } else { Button(configuration).buttonStyle(.glass) }
        }
    }
}

extension PrimitiveButtonStyle where Self == AdaptiveGlassButtonStyle {
    static var glassy: AdaptiveGlassButtonStyle { .init() }
}

// MARK: Clock

/// Periodic timeline aligned to wall-clock multiples of `interval`, which stops
/// ticking while `paused` (e.g. the window is hidden or fully covered).
struct Ticks: TimelineSchedule {
    var interval: TimeInterval
    var paused = false

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date? = start
        let paused = paused, interval = interval
        return AnyIterator {
            guard let current = next else { return nil }
            if paused {
                next = nil
            } else {
                let t = (current.timeIntervalSinceReferenceDate / interval).rounded(.down) * interval + interval
                next = Date(timeIntervalSinceReferenceDate: t)
            }
            return current
        }
    }
}

extension TimelineSchedule where Self == Ticks {
    static func every(_ interval: TimeInterval, paused: Bool = false) -> Ticks { Ticks(interval: interval, paused: paused) }
}
