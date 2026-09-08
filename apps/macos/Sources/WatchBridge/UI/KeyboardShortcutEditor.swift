import SwiftUI
import AppKit

@MainActor
struct KeyboardShortcutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchStore.self) private var store
    @State private var shortcut: KeyboardShortcut
    @State private var recorder = KeyboardRecording()
    @State private var manual = KeyboardShortcut()
    @State private var showingManual = false
    let onSave: (KeyboardShortcut) -> Void

    init(shortcut: KeyboardShortcut, manualExpanded: Bool = false, onSave: @escaping (KeyboardShortcut) -> Void) {
        _shortcut = State(initialValue: shortcut); _showingManual = State(initialValue: manualExpanded); self.onSave = onSave
    }
    private var steps: [KeyboardStep] { recorder.isRecording ? recorder.steps : shortcut.steps ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            SectionTitle(eyebrow: "Keyboard action", title: "Record your shortcut", detail: "Tap a key, a combination, or a sequence — including Command twice.")
            HStack(spacing: 12) {
                Button {
                    if recorder.isRecording { if let recorded = recorder.finish() { shortcut = recorded } }
                    else { recorder.start(); store.isRecordingKeyboard = recorder.isRecording }
                } label: {
                    Label(recorder.isRecording ? "Stop recording" : "Record", systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                }.buttonStyle(.accent).controlSize(.large).disabled(store.actionRunning)
                Text(recorder.message).font(.callout).foregroundStyle(recorder.isRecording ? Theme.accent : Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(index + 1)\(index == 0 ? " · Start" : " · +\(step.delayMs) ms")").font(.caption).foregroundStyle(Theme.text2)
                            Text(step.summary).font(.system(size: 19, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.text).lineLimit(2).minimumScaleFactor(0.7)
                        }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                            .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                if steps.isEmpty { Text("Your recorded keys will appear here.").foregroundStyle(Theme.text2).padding(24) }
            }.frame(height: 180).padding(12).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("⌘ → ⌘  Double Command") { shortcut = .recorded([.init(key: "meta"), .init(key: "meta", delayMs: 140)]) }
                Button("→ →  Right twice") { shortcut = .recorded([.init(key: "right"), .init(key: "right", delayMs: 100)]) }
                Spacer()
                Button("Undo last") {
                    var steps = shortcut.steps ?? []; if !steps.isEmpty { steps.removeLast() }; shortcut = .recorded(steps)
                }.disabled(steps.isEmpty)
            }.disabled(recorder.isRecording)
            DisclosureGroup("Add a key manually", isExpanded: $showingManual) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("Key", selection: $manual.key) {
                            ForEach(RustCore.keyboardKeys) { key in Text(key.display).tag(key.id) }
                        }
                        Stepper("\(manual.repetitions)×", value: $manual.repetitions, in: 1...10).fixedSize()
                        Button("Add") {
                            var steps = shortcut.steps ?? []
                            for var step in manual.steps ?? [] { if !steps.isEmpty && step.delayMs == 0 { step.delayMs = 100 }; steps.append(step) }
                            shortcut = .recorded(steps)
                        }.disabled(!manual.isValid || steps.count + manual.repetitions > 32)
                    }
                    HStack {
                        Toggle("⌃", isOn: $manual.control); Toggle("⌥", isOn: $manual.alt)
                        Toggle("⇧", isOn: $manual.shift); Toggle("⌘", isOn: $manual.meta)
                    }.toggleStyle(.button)
                }.padding(.top, 8)
            }.disabled(recorder.isRecording)
            Text("Recording stays in this editor and stops on focus loss. Up to 32 taps in 30 seconds; pauses are limited to 2 seconds. Physical key positions follow your keyboard layout. System-reserved shortcuts may need a preset; target apps can reject synthetic input.")
                .font(.caption).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            }.frame(height: 500)
            HStack {
                Button("Accessibility settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                }.buttonStyle(.ghost).disabled(recorder.isRecording)
                Spacer()
                Button("Cancel") { recorder.cancel(); dismiss() }
                Button("Save shortcut") { onSave(shortcut); dismiss() }
                    .buttonStyle(.accent).disabled(recorder.isRecording || !shortcut.isValid)
            }
            Text("Playback targets the focused app and needs Accessibility permission. Test waits 3 seconds so you can focus a safe window.")
                .font(.caption).foregroundStyle(Theme.text2)
        }.padding(24).frame(width: 690)
            .onChange(of: recorder.isRecording) { _, recording in store.isRecordingKeyboard = recording }
            .onDisappear { recorder.cancel(); store.isRecordingKeyboard = false }
    }
}
