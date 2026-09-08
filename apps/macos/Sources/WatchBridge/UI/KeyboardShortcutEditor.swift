import SwiftUI
import AppKit

/// A local key picker, not a key recorder: no global keyboard monitoring or text capture.
@MainActor
struct KeyboardShortcutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shortcut: KeyboardShortcut
    let onSave: (KeyboardShortcut) -> Void

    init(shortcut: KeyboardShortcut, onSave: @escaping (KeyboardShortcut) -> Void) {
        _shortcut = State(initialValue: shortcut)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(eyebrow: "Keyboard action", title: "Build your shortcut", detail: "Choose a key, add modifiers, then set the number of presses.")
            HStack {
                Label(shortcut.summary, systemImage: "keyboard")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Stepper("Repeat \(shortcut.repetitions)×", value: $shortcut.repetitions, in: 1...10)
                    .fixedSize()
            }
            .padding(16).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 6) {
                ForEach(0..<6) { row in
                    HStack(spacing: 5) {
                        ForEach(RustCore.keyboardKeys.filter { $0.row == row }) { key in
                            Button { shortcut.key = key.id } label: {
                                Text(key.label)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .frame(minWidth: key.label.count > 2 ? 42 : 30, maxWidth: .infinity, minHeight: 34)
                                    .foregroundStyle(shortcut.key == key.id ? Color.white : Theme.text)
                                    .background(shortcut.key == key.id ? Theme.accent : Theme.surface2, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.strokeStrong))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select \(key.id.replacingOccurrences(of: "_", with: " ")) key")
                            .accessibilityAddTraits(shortcut.key == key.id ? .isSelected : [])
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Toggle("⌃ Control", isOn: $shortcut.control)
                Toggle("⌥ Option", isOn: $shortcut.alt)
                Toggle("⇧ Shift", isOn: $shortcut.shift)
                Toggle("⌘ Command", isOn: $shortcut.meta)
            }
            .toggleStyle(.button)
            .controlSize(.large)

            Text("US reference key positions. Your keyboard layout determines letters and symbols. Fn, secure system shortcuts and typing arbitrary text are not supported.")
                .font(.caption).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            Label("Keys go to the focused app. Tests wait 3 seconds; use a safe window. Accessibility permission is required.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Accessibility settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.ghost)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save shortcut") { onSave(shortcut); dismiss() }
                    .buttonStyle(.accent).disabled(shortcut.definition == nil).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 690)
    }
}
