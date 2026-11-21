import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Megjelenés", systemImage: "paintbrush") { AppearanceSettings() }
            Tab("Általános", systemImage: "gearshape") { GeneralSettings() }
            Tab("Értesítések", systemImage: "bell.badge") { NotificationSettings() }
            Tab("Jegyek", systemImage: "graduationcap") { GradeSettings() }
            Tab("Oldalsáv", systemImage: "sidebar.left") { NavigationSettings() }
        }
        .frame(width: 560, height: 520)
    }
}

struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var look = model.look
        Form {
            Section {
                Picker("Téma", selection: $model.prefs.theme) {
                    ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Kiemelőszín") {
                    HStack(spacing: 8) {
                        ForEach(Palette.allCases) { p in
                            let selected = model.prefs.palette == p
                            Button { model.prefs.palette = p } label: {
                                Circle()
                                    .fill(p == .system ? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center)) : AnyShapeStyle(p.color))
                                    .frame(width: 16, height: 16)
                                    .overlay { if selected { Circle().fill(.white).frame(width: 6, height: 6) } }
                            }
                            .buttonStyle(.plain)
                            .help(p.label)
                        }
                    }
                }
                Picker("Címek betűtípusa", selection: $model.prefs.titleFont) {
                    ForEach(TitleFont.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                Picker("Háttér", selection: $look.backdrop) {
                    ForEach(WindowBackdrop.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                switch look.backdrop {
                case .translucent:
                    LabeledContent("Átlátszatlanság") {
                        HStack {
                            Slider(value: $look.opacity, in: 0...1)
                            Text("\(Int(look.opacity * 100))%").font(.mono(12)).frame(width: 40, alignment: .trailing)
                        }
                    }
                    LabeledContent("Elmosás") {
                        HStack {
                            Slider(value: $look.blur, in: 0...60)
                            Text("\(Int(look.blur))").font(.mono(12)).frame(width: 40, alignment: .trailing)
                        }
                    }
                    .disabled(!WindowBlur.isAvailable)
                    Toggle("Színezés a kiemelőszínnel", isOn: $look.tintWithAccent)
                    LabeledContent("Előbeállítás") {
                        HStack(spacing: 6) {
                            preset("Tiszta", opacity: 0.2, blur: 8)
                            preset("Matt", opacity: 0.55, blur: 24)
                            preset("Sűrű", opacity: 0.8, blur: 40)
                        }
                    }
                case .glass:
                    Text("A rendszer saját, a háttérhez igazodó anyaga.").foregroundStyle(.secondary)
                case .gradient:
                    ColorPicker("Első szín", selection: Binding(get: { Color(hexString: look.gradientColor1) },
                                                                 set: { look.gradientColor1 = $0.hexString }), supportsOpacity: false)
                    ColorPicker("Második szín", selection: Binding(get: { Color(hexString: look.gradientColor2) },
                                                                    set: { look.gradientColor2 = $0.hexString }), supportsOpacity: false)
                    Toggle("Lassan mozgó háttér", isOn: $look.animatedGradient)
                }
            } header: {
                Text("Ablak")
            } footer: {
                Text("A változás azonnal látszik a fő ablakon.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func preset(_ name: String, opacity: Double, blur: Double) -> some View {
        Button(name) {
            model.look.opacity = opacity
            model.look.blur = blur
        }
        .controlSize(.small)
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Háttérfrissítés") {
                Stepper(value: $model.prefs.pollIntervalMinutes, in: 1...60) {
                    LabeledContent("Frissítés gyakorisága", value: "\(model.prefs.pollIntervalMinutes) percenként")
                }
                Toggle("Háttérfrissítés szüneteltetése", isOn: $model.paused)
            }
            Section("Indítás") {
                Toggle("Indítás bejelentkezéskor", isOn: $model.prefs.launchAtLogin)
                Toggle("Indítás csak a menüsorban", isOn: $model.prefs.startMinimized)
            }
            Section {
                Stepper(value: $model.prefs.bellOffsetMinutes, in: -30...30) {
                    LabeledContent("Csengő eltérése", value: "\(model.prefs.bellOffsetMinutes > 0 ? "+" : "")\(model.prefs.bellOffsetMinutes) perc")
                }
            } footer: {
                Text("Ha az iskola csengője siet vagy késik, a visszaszámlálás ehhez igazodik.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct NotificationSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Értesítések", isOn: $model.prefs.notificationsEnabled)
                Button("Próbaértesítés küldése") { model.sendTestNotification() }
            }
            Section("Kategóriák") {
                ForEach(NotificationCategory.allCases) { c in
                    Toggle(c.label, isOn: Binding(
                        get: { model.prefs.notificationCategories.contains(c) },
                        set: { on in if on { model.prefs.notificationCategories.insert(c) } else { model.prefs.notificationCategories.remove(c) } }))
                }
            }
            .disabled(!model.prefs.notificationsEnabled)
            Section {
                let subjects = Array(Set(model.diary.grades.map(\.subject) + model.prefs.mutedSubjects)).sorted { $0.compare($1, locale: Format.hu) == .orderedAscending }
                if subjects.isEmpty { Text("Az első szinkronizálás után jelennek meg a tantárgyak.").foregroundStyle(.secondary) }
                ForEach(subjects, id: \.self) { s in
                    Toggle(s, isOn: Binding(
                        get: { model.prefs.mutedSubjects.contains(s) },
                        set: { on in
                            model.prefs.mutedSubjects.removeAll { $0 == s }
                            if on { model.prefs.mutedSubjects.append(s) }
                        }))
                }
            } header: {
                Text("Némított tantárgyak")
            } footer: {
                Text("Ezekből a tárgyakból nem kapsz értesítést jegyről, házi feladatról vagy dolgozatról.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct GradeSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Jegyek elrejtése", isOn: $model.prefs.privateGrades)
            } footer: {
                Text("A jegyek és átlagok rejtve maradnak, amíg rájuk nem kattintasz. Az értesítések sem mutatják őket.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ForEach(0..<4, id: \.self) { i in
                    LabeledContent("\(i + 2)-es ettől") {
                        HStack {
                            Slider(value: threshold(i), in: 1...5, step: 0.05)
                            Text(Format.decimal(model.prefs.gradeThresholds[i])).monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Button("Alapértékek") { withAnimation { model.prefs.gradeThresholds = [1.5, 2.5, 3.5, 4.5] } }
            } header: {
                Text("Kerekítési határok")
            } footer: {
                Text("Csak helyi becslés a várható év végi jegyhez — nem hivatalos.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Keeps thresholds strictly increasing while dragging.
    private func threshold(_ i: Int) -> Binding<Double> {
        Binding(get: { model.prefs.gradeThresholds[i] }, set: { v in
            var t = model.prefs.gradeThresholds
            let lo = i > 0 ? t[i - 1] + 0.05 : 1, hi = i < 3 ? t[i + 1] - 0.05 : 5
            t[i] = min(hi, max(lo, v))
            model.prefs.gradeThresholds = t
        })
    }
}

struct NavigationSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(Page.allCases.filter { $0 != .dashboard }) { p in
                    Toggle(isOn: Binding(
                        get: { !model.prefs.hiddenPages.contains(p) },
                        set: { on in withAnimation(.smooth) { if on { model.prefs.hiddenPages.remove(p) } else { model.prefs.hiddenPages.insert(p) } } })) {
                        Label(p.label, systemImage: p.icon)
                    }
                }
            } header: {
                Text("Látható oldalak")
            } footer: {
                Text("A rejtett oldalak a Napló menüből továbbra is elérhetők.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
