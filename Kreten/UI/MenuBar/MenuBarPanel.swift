import SwiftUI

/// Compact glass panel in the menu bar: live lesson, quick stats and background controls.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image("Logo").resizable().renderingMode(.template).scaledToFit().frame(height: 16)
                Spacer()
                if model.syncing { ProgressView().controlSize(.small) }
                else if let last = model.snapshot.lastSyncedAt {
                    Text(Format.relative(last)).font(.mono(10)).foregroundStyle(.secondary)
                }
            }

            if model.hasAccount {
                TimelineView(.every(1)) { ctx in
                    let now = model.schoolNow(ctx.date)
                    let live = LiveStatus.compute(model.diary.timeline, now: now)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(live.label).font(.mono(10, .medium)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Text(live.title).font(.title3.bold()).lineLimit(1)
                            Spacer()
                            if let end = live.end, live.kind != .empty {
                                let t = max(0, Int(end.timeIntervalSince(now)))
                                Text(t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%02d:%02d", t / 60, t % 60))
                                    .font(.mono(16, .medium))
                                    .contentTransition(.numericText(countsDown: true))
                            }
                        }
                        Text(live.details).font(.mono(11)).foregroundStyle(.secondary).lineLimit(1)
                        if live.kind == .lesson || live.kind == .breakTime {
                            Meter(value: live.progress(at: now), color: live.kind == .breakTime ? .orange : Color.accentColor, height: 5)
                        }
                    }
                    .padding(12)
                    .surface(.rect(cornerRadius: 16), tint: Color.accentColor.opacity(0.1))
                }

                HStack(spacing: 8) {
                    QuickStat(value: "\(model.diary.lessons.filter { $0.date == Day.today && !$0.cancelled }.count)", label: "mai óra")
                    QuickStat(value: "\(model.diary.homework.filter { !model.isDone($0) && $0.date >= Day.today }.count)", label: "házi")
                    QuickStat(value: "\(model.snapshot.notifications.count)", label: "értesítés")
                }
            } else {
                Text("Jelentkezz be a KRETÉN ablakában.").font(.callout).foregroundStyle(.secondary)
            }

            Divider()
            VStack(spacing: 2) {
                MenuRow(title: "KRETÉN megnyitása", icon: "macwindow") { show() }
                MenuRow(title: "Frissítés most", icon: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(!model.hasAccount || model.syncing)
                Toggle(isOn: $model.paused) {
                    Label("Háttérfrissítés szüneteltetése", systemImage: "pause.circle")
                }
                .toggleStyle(.switch).controlSize(.mini)
                .padding(.horizontal, 8).padding(.vertical, 5)
                SettingsLink {
                    Label("Beállítások…", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 5).contentShape(.rect)
                }
                .buttonStyle(.plain)
                Divider()
                MenuRow(title: "Kilépés", icon: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

private struct QuickStat: View {
    var value: String
    var label: String
    var body: some View {
        VStack(spacing: 0) {
            Text(value).font(.mono(16, .medium))
            Text(label).font(.mono(10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .surface(.rect(cornerRadius: 12))
    }
}

private struct MenuRow: View {
    var title: String
    var icon: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(hover ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
