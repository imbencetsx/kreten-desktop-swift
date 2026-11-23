import CoreText
import SwiftUI

// MARK: Typography

/// Bundled Geist Mono, loaded straight from the app's own font files. Fonts are
/// never looked up by name: a same-named copy in ~/Library/Fonts would win the
/// lookup, and the sandbox can't read that file, so text would silently fall back.
@MainActor
enum Typeface {
    enum Weight: String, CaseIterable { case regular = "Regular", medium = "Medium", semibold = "SemiBold" }

    static let descriptors: [Weight: CTFontDescriptor] = {
        var out: [Weight: CTFontDescriptor] = [:]
        for w in Weight.allCases {
            guard let url = Bundle.main.url(forResource: "GeistMonoNerdFontMono-\(w.rawValue)", withExtension: "otf"),
                  let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let d = list.first else { continue }
            out[w] = d
        }
        return out
    }()
}

extension Font {
    @MainActor private static var monoCache: [String: Font] = [:]

    /// Geist Mono for secondary, data-like text: dates, times, counts, labels.
    /// Cached: every row asks for these, and each new CTFont is a fresh font
    /// object SwiftUI can't recognize as unchanged.
    @MainActor static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let w: Typeface.Weight = switch weight {
        case .medium: .medium
        case .semibold, .bold, .heavy, .black: .semibold
        default: .regular
        }
        let key = "\(w.rawValue)/\(size)"
        if let font = monoCache[key] { return font }
        let font: Font = if let d = Typeface.descriptors[w] {
            Font(CTFontCreateWithFontDescriptor(d, size, nil))
        } else {
            .system(size: size, weight: weight, design: .monospaced)
        }
        monoCache[key] = font
        return font
    }
}

// MARK: Page scaffold

/// Scrollable page with a large header. Content floats on the window backdrop.
struct PageScaffold<Actions: View, Content: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String?
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content
    @Environment(AppModel.self) private var model
    @Environment(\.reducedEffects) private var reduced

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(eyebrow.uppercased())
                            .font(.mono(11, .medium))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.system(size: 30, weight: .bold, design: model.prefs.titleFont.design))
                            .lineLimit(2)
                        if let subtitle {
                            Text(subtitle).font(.body).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    actions
                }
                .padding(.bottom, 4)
                // Share the sampling pass while keeping neighboring cards distinct.
                GlassEffectContainer(spacing: 8) {
                    VStack(alignment: .leading, spacing: 20) { content }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 36)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // The soft edge blurs content scrolling under the toolbar on every frame.
        .scrollEdgeEffectStyle(reduced ? .hard : .soft, for: .top)
    }
}

extension PageScaffold where Actions == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, actions: { EmptyView() }, content: content)
    }
}

// MARK: Panels

/// Shared surface for cards and standalone panels (Liquid Glass, or flat with
/// reduced effects). Keep it behind the content so labels keep full contrast.
extension View {
    func panel(radius: CGFloat = 16) -> some View { surface(.rect(cornerRadius: radius)) }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
    }
}

struct CardHeader<Trailing: View>: View {
    var title: String
    var count: Int?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.headline)
            if let count, count > 0 {
                Text("\(count)").font(.mono(12, .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String, count: Int? = nil) { self.init(title: title, count: count) { EmptyView() } }
}

/// Quiet text link ("Mind →").
struct LinkButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.tint)
    }
}

/// Row with a subtle hover highlight.
struct RowButton<Content: View>: View {
    var action: () -> Void
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hover ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(.horizontal, -8)
    }
}

// MARK: Grades

/// System colors, the way KRÉTA users read them: 5 green … 1 red.
func gradeColor(_ value: Int) -> Color {
    switch value {
    case 5: .green
    case 4: .mint
    case 3: .yellow
    case 2: .orange
    case 1: .red
    default: .secondary
    }
}

func averageColor(_ value: Double?) -> Color {
    guard let value else { return .secondary }
    return gradeColor(Int(value.rounded()))
}

struct GradeBadge: View {
    var grade: Grade
    var size: CGFloat = 32
    @Environment(AppModel.self) private var model

    var body: some View {
        let hidden = model.gradesHidden
        let color = grade.isNumeric && !hidden ? gradeColor(grade.value) : Color.secondary
        let text = hidden ? "·" : (grade.display.isEmpty ? "–" : String(grade.display.prefix(grade.isNumeric ? 1 : 4)))
        Text(text)
            .font(grade.isNumeric || hidden ? .system(size: size * 0.5, weight: .semibold, design: .rounded) : .mono(size * 0.3, .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .surface(.rect(cornerRadius: size * 0.3), tint: color.opacity(hidden ? 0.08 : 0.2))
            .onTapGesture { if hidden { model.revealGrades() } }
            .accessibilityLabel(hidden ? "Rejtett jegy" : "Jegy: \(grade.display)")
    }
}

/// Small colored label.
struct Pill: View {
    var text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.mono(11, .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.14), in: .rect(cornerRadius: 5))
            .foregroundStyle(color)
    }
}

/// Masks grade-derived values while private mode is on; click to reveal.
struct PrivateText: View {
    var text: String
    var font: Font = .body
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(model.gradesHidden ? "•,••" : text)
            .font(font)
            .monospacedDigit()
            .blur(radius: model.gradesHidden ? 6 : 0)
            .onTapGesture { if model.gradesHidden { model.revealGrades() } }
            .help(model.gradesHidden ? "Kattints a felfedéshez" : "")
    }
}

// MARK: Stats

struct StatTile: View {
    var label: String
    var value: String
    var note: String
    var isPrivate = false

    var body: some View {
        Card {
            Text(label.uppercased()).font(.mono(11, .medium)).foregroundStyle(.secondary)
            Group {
                if isPrivate { PrivateText(text: value, font: .system(size: 28, weight: .semibold)) }
                else { Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit() }
            }
            Text(note).font(.mono(11)).foregroundStyle(.tertiary)
        }
    }
}

/// Quiet one-liner for empty lists.
struct EmptyState: View {
    var title: String
    var text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            if let text { Text(text).font(.mono(11)).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

/// Label/value pairs, e.g. profile fields and detail sheets.
struct InfoGrid: View {
    var rows: [(String, String)]
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 9) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0.uppercased()).font(.mono(11, .medium)).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                    Text(row.1.isEmpty ? "—" : row.1).font(.callout).textSelection(.enabled)
                }
            }
        }
    }
}

/// Native search field in a glass capsule.
struct GlassSearchField: View {
    var prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .frame(maxWidth: 260)
        .surface(.capsule)
    }
}

/// Thin horizontal meter.
struct Meter: View {
    var value: Double // 0...1
    var color: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        Capsule().fill(Color.primary.opacity(0.08))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(color).frame(width: max(height, geo.size.width * min(1, max(0, value))))
                }
            }
            .frame(height: height)
    }
}

/// Sheet chrome shared by detail sheets.
struct DetailSheet<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.bold())
                    if let subtitle { Text(subtitle).font(.mono(12)).foregroundStyle(.secondary) }
                }
                Spacer()
                Button("Kész") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            content
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 520)
    }
}
