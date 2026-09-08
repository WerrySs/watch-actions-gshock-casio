import AppKit
import ApplicationServices

enum KeyboardEmitter {
    struct Stroke {
        var code: CGKeyCode
        var down: Bool
        var flags: CGEventFlags
        var modifier: Bool
    }

    /// Pure plan: allocate every down/up event before posting any of them.
    static func plan(_ shortcut: KeyboardShortcut) -> [Stroke]? {
        guard let key = shortcut.definition else { return nil }
        let modifiers: [(Bool, CGKeyCode, CGEventFlags)] = [
            (shortcut.control, 59, .maskControl), (shortcut.alt, 58, .maskAlternate),
            (shortcut.shift, 56, .maskShift), (shortcut.meta, 55, .maskCommand)
        ]
        var flags: CGEventFlags = []
        var strokes: [Stroke] = []
        for (enabled, code, flag) in modifiers where enabled {
            flags.insert(flag)
            strokes.append(Stroke(code: code, down: true, flags: flags, modifier: true))
        }
        strokes.append(Stroke(code: key.macCode, down: true, flags: flags, modifier: false))
        strokes.append(Stroke(code: key.macCode, down: false, flags: flags, modifier: false))
        for (enabled, code, flag) in modifiers.reversed() where enabled {
            flags.remove(flag)
            strokes.append(Stroke(code: code, down: false, flags: flags, modifier: true))
        }
        return strokes
    }

    @MainActor
    static func run(_ shortcut: KeyboardShortcut?) async -> String {
        guard let shortcut, let key = shortcut.definition, let plan = plan(shortcut) else {
            return "keyboard blocked: invalid key or repetition count"
        }
        guard AXIsProcessTrusted() else { return "keyboard needs Accessibility permission for WatchBridge in System Settings" }
        guard let target = NSWorkspace.shared.frontmostApplication,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return "keyboard blocked: focus another application first"
        }
        guard let source = CGEventSource(stateID: .privateState) else { return "could not create the keyboard event source" }
        var events: [CGEvent] = []
        for stroke in plan {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.code, keyDown: stroke.down) else {
                return "could not prepare a complete keyboard request"
            }
            event.flags = stroke.flags
            if stroke.modifier { event.type = .flagsChanged }
            events.append(event)
        }
        let physicalModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        for repetition in 0..<shortcut.repetitions {
            guard !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                return "keyboard stopped: the focused application changed"
            }
            guard CGEventSource.flagsState(.combinedSessionState).intersection(physicalModifiers).isEmpty,
                  !CGEventSource.keyState(.combinedSessionState, key: key.macCode) else {
                return "keyboard stopped: release held keys and try again"
            }
            // No suspension between key-down and the final modifier release.
            for event in events { event.post(tap: .cghidEventTap) }
            if repetition + 1 < shortcut.repetitions {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return "keyboard request cancelled after releasing its keys" }
            }
        }
        return "keyboard request sent (\(shortcut.repetitions) repetitions); the target app decides how to handle it"
    }
}
