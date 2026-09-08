import SwiftUI

@MainActor
struct ActionsView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ActionLayerControls()
                DisclosureGroup("Watch button guide") { WatchButtonGuide().padding(.top, 10) }
                    .font(.callout).foregroundStyle(Theme.text2)
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(
                        eyebrow: "Actions",
                        title: "What the Mac does for each gesture",
                        detail: "actions begin as soon as the gesture is read"
                    )
                    Label(
                        "Only physical watches you explicitly trust in My Watches may run actions. Test is always manual.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 14
                    ) {
                        ForEach(WatchButtonEvent.configurable) { event in
                            ActionEditor(event: event, equalized: true, layer: store.editingLayer)
                                .frame(height: 318)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(eyebrow: "Time", title: "When to send the Mac time to the watch")
                    Tile {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(WatchButtonEvent.configurable) { event in
                                HStack(spacing: 12) {
                                    GestureBadge(event: event)
                                    Text(event.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                                    Spacer()
                                    Toggle(isOn: Binding(
                                        get: { store.config.syncTimeOn.contains(event) },
                                        set: { store.setSyncTime($0, for: event) })) { EmptyView() }
                                        .toggleStyle(.accentSwitch)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Fine adjustment").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                                    Text("Seconds added to compensate for connection latency.").font(.system(size: 11)).foregroundStyle(Theme.text2)
                                }
                                Spacer()
                                Stepper(value: Binding(get: { store.config.timeOffsetSeconds }, set: { store.setTimeOffset($0) }), in: -30...30) {
                                    Text("\(store.config.timeOffsetSeconds) s").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            Text("The watch may disconnect after receiving the time, so WatchBridge always sends it last.")
                                .font(.system(size: 11)).foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
            .padding(26)
        }
    }
}

/// Editor for one gesture. Equalized cards reserve the same space for optional controls.
@MainActor
struct ActionEditor: View {
    @Environment(WatchStore.self) private var store
    let event: WatchButtonEvent
    var equalized = false
    var layer: ActionLayer = .normal
    @State private var showingKeyboard = false

    var body: some View {
        let action = store.config.action(for: event, layer: layer)
        let isSwitch = store.config.switchEvent == event
        Tile(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    GestureBadge(event: event, highlighted: store.lastEvent == event && store.phase == .connected, large: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(event.gesture).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        store.testAction(for: event, layer: layer)
                    } label: { Label("Test", systemImage: "play.fill") }
                        .buttonStyle(.ghost)
                        .disabled(action.kind == .none || isSwitch || store.actionRunning)
                        .help("Run this action now without touching the watch")
                }
                .frame(minHeight: equalized ? 88 : nil, alignment: .top)

                FieldLabel(label: isSwitch ? "Reserved in all modes" : (event == .auto ? "Computer action · Normal only" : "Computer action")) {
                    if isSwitch {
                        Label("Cycle to the next mode", systemImage: "square.2.layers.3d")
                            .font(.callout.weight(.semibold)).foregroundStyle(Theme.accent)
                            .frame(height: 28)
                    } else {
                        Picker("", selection: Binding(
                            get: { action.kind },
                            set: { store.setAction(WatchAction(kind: $0, value: $0.needsValue ? action.value : "", keyboard: $0 == .keyboard ? action.keyboard ?? KeyboardShortcut() : action.keyboard), for: event, layer: layer) })) {
                            ForEach(ActionKind.allCases) { kind in
                                Label(kind.label, systemImage: kind.systemImage).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.large)
                        .frame(height: 28)
                    }
                }
                if isSwitch {
                    Text("The saved computer action is paused. Use the same gesture to switch back.")
                        .font(.callout).foregroundStyle(Theme.text2).frame(minHeight: 48)
                } else if action.kind == .keyboard {
                    Button { showingKeyboard = true } label: {
                        HStack { Label(action.summary, systemImage: "keyboard"); Spacer(); Image(systemName: "slider.horizontal.3") }
                    }
                    .buttonStyle(.ghost).help("Choose keys, modifiers and repetitions")
                    .frame(minHeight: 48)
                } else if action.kind.needsValue {
                    FieldLabel(label: action.kind.valuePrompt) {
                        DarkField(placeholder: action.kind.valuePrompt,
                                  text: Binding(get: { action.value }, set: { store.setAction(WatchAction(kind: action.kind, value: $0), for: event, layer: layer) }),
                                  font: .system(size: 15, weight: .medium))
                    }
                } else if equalized {
                    FieldLabel(label: "Action value") {
                        DarkField(placeholder: "Not required for this action", text: .constant(""))
                            .disabled(true)
                    }
                    .hidden()
                }
                if equalized { Spacer(minLength: 0) }
                if !isSwitch && !hint(for: action.kind).isEmpty {
                    Label(hint(for: action.kind), systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: equalized ? 38 : nil, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: equalized ? .infinity : nil, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingKeyboard) {
            KeyboardShortcutEditor(shortcut: action.keyboard ?? KeyboardShortcut()) { shortcut in
                store.setAction(WatchAction(kind: .keyboard, keyboard: shortcut), for: event, layer: layer)
            }
        }
    }

    private func hint(for kind: ActionKind) -> String {
        switch kind {
        case .shortcut: "The name must match an item in the Shortcuts app."
        case .sound: "Requests attention, plays three alerts, and says “Here I am”."
        case .say: "The Mac speaks the configured phrase aloud."
        case .none: "No computer action runs for this gesture."
        case .keyboard: "Keys target the focused app. Test waits 3 seconds; release held modifiers first."
        default: ""
        }
    }
}


/// Neutral diagram that makes physical button positions clear without manufacturer photography.
@MainActor
private struct WatchButtonGuide: View {
    var body: some View {
        Tile(padding: 18) {
            HStack(spacing: 28) {
                WatchButtonDiagram()
                    .frame(width: 205, height: 175)

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(
                        eyebrow: "Watch guide",
                        title: "Where each button is",
                        detail: "C and D can start actions on the Mac"
                    )
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            guideRow(letter: "A", title: "Upper left", detail: "Watch settings.", events: [])
                            guideRow(letter: "C", title: "Lower left", detail: "Hold 3 seconds: CNCT.", events: [.leftLong])
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            guideRow(letter: "B", title: "Upper right", detail: "Watch light.", events: [])
                            guideRow(letter: "D", title: "Lower right", detail: "Press: TIME · hold 5 seconds: FIND.", events: [.rightShort, .find])
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func guideRow(letter: String, title: String, detail: String, events: [WatchButtonEvent]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(letter)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(events.isEmpty ? Theme.text2 : Theme.accent)
                .frame(width: 24, height: 24)
                .background(events.isEmpty ? Theme.surface3 : Theme.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                    ForEach(events) { GestureBadge(event: $0) }
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
        }
    }
}

@MainActor
private struct WatchButtonDiagram: View {
    var body: some View {
        ZStack {
            if let image = WatchImageStore.buttonGuideImage() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 175)
            }
            marker("A", active: false).offset(x: -76, y: -38)
            marker("B", active: false).offset(x: 76, y: -38)
            marker("C", active: true).offset(x: -76, y: 43)
            marker("D", active: true).offset(x: 76, y: 43)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Watch diagram: A upper left, B upper right, C lower left, and D lower right")
    }

    private func marker(_ letter: String, active: Bool) -> some View {
        Text(letter)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(active ? Color.white : Theme.text2)
            .frame(width: 30, height: 30)
            .background(active ? Theme.accent : Theme.surface3, in: Circle())
            .overlay(Circle().strokeBorder(active ? Theme.accent.opacity(0.8) : Theme.strokeStrong, lineWidth: 1))
            .shadow(color: active ? Theme.accent.opacity(0.25) : .clear, radius: 8)
    }
}
