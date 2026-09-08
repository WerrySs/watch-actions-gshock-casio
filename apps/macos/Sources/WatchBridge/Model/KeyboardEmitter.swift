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
        guard let steps = shortcut.steps else { return nil }
        return steps.flatMap { plan($0) ?? [] }
    }
    static func plan(_ step: KeyboardStep) -> [Stroke]? {
        guard let key = step.definition else { return nil }
        let modifiers: [(Bool, CGKeyCode, CGEventFlags)] = [
            (step.modifiers & 1 != 0, 59, .maskControl), (step.modifiers & 2 != 0, 58, .maskAlternate),
            (step.modifiers & 4 != 0, 56, .maskShift), (step.modifiers & 8 != 0, 55, .maskCommand)
        ]
        var flags: CGEventFlags = []
        var strokes: [Stroke] = []
        for (enabled, code, flag) in modifiers where enabled {
            flags.insert(flag)
            strokes.append(Stroke(code: code, down: true, flags: flags, modifier: true))
        }
        let keyFlag: CGEventFlags = switch key.modifier { case 1: .maskControl; case 2: .maskAlternate; case 4: .maskShift; case 8: .maskCommand; default: [] }
        strokes.append(Stroke(code: key.macCode, down: true, flags: flags.union(keyFlag), modifier: key.modifier != 0))
        strokes.append(Stroke(code: key.macCode, down: false, flags: flags, modifier: key.modifier != 0))
        for (enabled, code, flag) in modifiers.reversed() where enabled {
            flags.remove(flag)
            strokes.append(Stroke(code: code, down: false, flags: flags, modifier: true))
        }
        return strokes
    }

    @MainActor
    static func run(_ shortcut: KeyboardShortcut?) async -> String {
        guard let shortcut, let steps = shortcut.steps else {
            return "keyboard blocked: invalid or incomplete shortcut"
        }
        guard AXIsProcessTrusted() else { return "keyboard needs Accessibility permission for WatchBridge in System Settings" }
        guard let target = NSWorkspace.shared.frontmostApplication,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return "keyboard blocked: focus another application first"
        }
        guard let source = CGEventSource(stateID: .privateState) else { return "could not create the keyboard event source" }
        var eventGroups: [[CGEvent]] = []
        for step in steps {
            guard let strokes = plan(step) else { return "could not plan the complete recording" }
            var events: [CGEvent] = []
            for stroke in strokes {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.code, keyDown: stroke.down) else {
                    return "could not prepare a complete keyboard request"
                }
                event.flags = stroke.flags
                if stroke.modifier { event.type = .flagsChanged }
                events.append(event)
            }
            eventGroups.append(events)
        }
        let physicalModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        for (index, step) in steps.enumerated() {
            if step.delayMs > 0 {
                do { try await Task.sleep(for: .milliseconds(step.delayMs)) }
                catch { return "keyboard request cancelled after releasing its keys" }
            }
            guard !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                return "keyboard stopped: the focused application changed"
            }
            guard CGEventSource.flagsState(.combinedSessionState).intersection(physicalModifiers).isEmpty,
                  let key = step.definition, !CGEventSource.keyState(.combinedSessionState, key: key.macCode) else {
                return "keyboard stopped: release held keys and try again"
            }
            // No suspension between key-down and the final modifier release.
            for event in eventGroups[index] {
                event.timestamp = DispatchTime.now().uptimeNanoseconds
                event.post(tap: .cghidEventTap)
            }
        }
        return "keyboard request sent (\(steps.count) steps); the target app decides how to handle it"
    }
}
