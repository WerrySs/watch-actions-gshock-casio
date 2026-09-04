import ServiceManagement
import SwiftUI

@MainActor
struct TimerSettingsView: View {
    @Environment(WatchStore.self) private var store
    @State private var minutes = 5
    @State private var seconds = 0
    @State private var draft = WatchSettings()
    @State private var settingsDirty = false
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top, spacing: 14) {
                    timerTile
                    timeTile
                }
                settingsSection
                appTile
            }
            .padding(26)
        }
        .onAppear { syncFromStore() }
        .onChange(of: store.timerSeconds) { syncFromStore() }
        .onChange(of: store.settings) { if !settingsDirty { syncFromStore() } }
    }

    private func syncFromStore() {
        if let t = store.timerSeconds { minutes = t / 60; seconds = t % 60 }
        if let s = store.settings, !settingsDirty { draft = s }
    }

    private var timerTile: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(eyebrow: "Timer", title: "Countdown")
            Tile {
                VStack(alignment: .leading, spacing: 14) {
                    LCDText(text: String(format: "%d:%02d", minutes, seconds), size: 30)
                    HStack(spacing: 14) {
                        FieldLabel(label: "Minutes") {
                            Stepper(value: $minutes, in: 0...1439) { Text("\(minutes)").font(.system(size: 13, weight: .semibold, design: .monospaced)).frame(width: 40, alignment: .leading) }
                        }
                        FieldLabel(label: "Seconds") {
                            Stepper(value: $seconds, in: 0...59) { Text("\(seconds)").font(.system(size: 13, weight: .semibold, design: .monospaced)).frame(width: 40, alignment: .leading) }
                        }
                        Spacer()
                        Button {
                            Task { await store.save(.timer(minutes * 60 + seconds)) }
                        } label: { Label("Save", systemImage: "arrow.up.circle.fill") }
                            .buttonStyle(.accent)
                    }
                    if let t = store.timerSeconds {
                        Text("Currently on the watch: \(Formatters.duration(t))").font(.system(size: 11)).foregroundStyle(Theme.text3)
                    }
                }
            }
        }
    }

    private var timeTile: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(eyebrow: "Time", title: "Automatic adjustment")
            Tile {
                VStack(alignment: .leading, spacing: 10) {
                    ToggleRow(title: "Automatic time adjustment",
                              subtitle: "Supported watches connect around 00:30, 06:30, 12:30, and 18:30",
                              icon: "clock.arrow.2.circlepath",
                              isOn: Binding(get: { store.autoTimeAdjust ?? true },
                                            set: { on in Task { await store.save(.autoTimeAdjust(on)) } }))
                        .disabled(store.autoTimeAdjust == nil)
                    HStack {
                        FieldLabel(label: "Home city") { Text(store.homeCity.map { $0.capitalized } ?? "—").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text) }
                        Spacer()
                        FieldLabel(label: "Last time sent") { Text(store.lastTimeSync.map { Formatters.dateTime.string(from: $0) } ?? "—").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text) }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(eyebrow: "Watch settings", title: "Display and sound")
                Spacer()
                if store.settings == nil {
                    Label("Hold C for 3 seconds to read current settings", systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(Theme.warn)
                }
            }
            Tile {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ToggleRow(title: "24-hour format", icon: "24.circle", isOn: $draft.twentyFourHour)
                        ToggleRow(title: "Button tone", icon: "speaker.wave.2", isOn: $draft.buttonTone)
                        ToggleRow(title: "Power saving", icon: "leaf", isOn: $draft.powerSaving)
                        ToggleRow(title: "Automatic wrist light", icon: "lightbulb", isOn: $draft.autoLight)
                        ToggleRow(title: "Long light, 4 seconds", icon: "sun.max", isOn: $draft.longLight)
                        ToggleRow(title: "Day / month date", icon: "calendar", isOn: $draft.dayFirstDate)
                    }
                    HStack {
                        FieldLabel(label: "Weekday language") {
                            Picker("", selection: $draft.language) {
                                ForEach(Array(WatchSettings.languages.enumerated()), id: \.offset) { i, name in Text(name).tag(i) }
                            }
                            .labelsHidden().frame(width: 180)
                        }
                        Spacer()
                        if settingsDirty { Text("Unsaved").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.warn) }
                        Button {
                            Task { await store.save(.settings(draft)); settingsDirty = false }
                        } label: { Label("Save settings", systemImage: "arrow.up.circle.fill") }
                            .buttonStyle(.accent)
                            .disabled(store.settings == nil || !settingsDirty)
                    }
                }
                .disabled(store.settings == nil)
                .onChange(of: draft) { settingsDirty = draft != store.settings }
            }
        }
    }

    private var appTile: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(eyebrow: "WatchBridge on this Mac", title: "Application")
            Tile {
                VStack(alignment: .leading, spacing: 10) {
                    ToggleRow(title: "Open WatchBridge at login", subtitle: "It also lives in the menu bar, so closing the window does not stop watch discovery",
                              icon: "power", isOn: Binding(get: { loginItem }, set: { setLoginItem($0) }))
                    if let loginError { Text(loginError).font(.system(size: 11)).foregroundStyle(Theme.bad) }
                    Divider().overlay(Theme.stroke)
                    Label("Private by design", systemImage: "hand.raised.square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Watch data, connection history, actions, and sanitized watch photos stay on this Mac. WatchBridge does not include analytics or upload them.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("WatchBridge is an independent community project. It is not affiliated with, authorized by, sponsored by, endorsed by, or supported by Casio Computer Co., Ltd. Brand names are used only to describe compatibility.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItem = on
            loginError = nil
        } catch {
            loginError = "The login setting could not be changed: \(error.localizedDescription)"
        }
    }
}
