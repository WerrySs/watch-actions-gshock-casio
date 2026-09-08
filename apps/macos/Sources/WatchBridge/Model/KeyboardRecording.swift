import AppKit
import Observation

/// Consumes only this editor's local events between Record and Stop. No global hooks or text capture.
@MainActor @Observable
final class KeyboardRecording {
    private(set) var isRecording = false
    private(set) var steps: [KeyboardStep] = []
    private(set) var idle = true
    var message = "Click Record, press your shortcut, then click Stop."
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var events: [RustCore.RecordedEvent] = []
    @ObservationIgnored private var held = Set<UInt16>()
    @ObservationIgnored private var started = 0.0
    @ObservationIgnored private weak var window: NSWindow?

    func start() {
        cancel()
        guard let window = NSApp.keyWindow, NSApp.isActive else { message = "Focus this editor first."; return }
        guard NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            message = "Release modifier keys before recording."; return
        }
        self.window = window; events = []; steps = []; held = []; idle = true
        started = ProcessInfo.processInfo.systemUptime; isRecording = true
        message = "Recording… press and release keys. Esc cancels. Never enter passwords."
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.receive(event) == nil
            }
            return consumed ? nil : event
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel(message: "Recording cancelled because the editor lost focus. Use a preset for system-reserved shortcuts.") }
            })
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            self?.cancel(message: "Recording cancelled after 30 seconds. Keep shortcuts short.")
        }
    }
    private func receive(_ event: NSEvent) -> NSEvent? {
        guard isRecording, NSApp.isActive, let window, window.isKeyWindow,
              event.window == nil || event.window === window else { return event }
        if event.type == .keyDown && event.keyCode == 53 { cancel(message: "Recording cancelled. Your saved shortcut is unchanged."); return nil }
        if event.type == .keyDown && event.isARepeat { return nil }
        guard let key = RustCore.keyboardKeys.first(where: { $0.macCode == event.keyCode }) else {
            cancel(message: "This key is not supported. Record again using standard keys and modifiers."); return nil
        }
        let down: Bool
        if event.type == .flagsChanged {
            guard key.modifier != 0 else { return nil }
            let flag: NSEvent.ModifierFlags = switch key.modifier { case 1: .control; case 2: .option; case 4: .shift; default: .command }
            down = event.modifierFlags.contains(flag) && !held.contains(event.keyCode)
        } else { down = event.type == .keyDown }
        if down { held.insert(event.keyCode) } else { held.remove(event.keyCode) }
        events.append(.init(key: key.id, down: down, time_ms: UInt64(max(0, (ProcessInfo.processInfo.systemUptime - started) * 1000))))
        guard let result = RustCore.recordKeys(events) else { cancel(message: "Could not read recording data. Record again."); return nil }
        if let error = result.error { cancel(message: error + ". Record again."); return nil }
        steps = result.steps; idle = result.idle
        message = "Recording · \(steps.count)/32 steps\(idle ? " · click Stop when finished" : " · release held keys")"
        return nil
    }
    func finish() -> KeyboardShortcut? {
        guard isRecording, idle, !steps.isEmpty else { message = "Release every key and record at least one tap before stopping."; return nil }
        let result = KeyboardShortcut.recorded(steps)
        cancel(message: "Recorded. Review the steps, then save.")
        return result.isValid ? result : nil
    }
    func cancel(message: String? = nil) {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        timeout?.cancel(); timeout = nil; window = nil
        events = []; held = []; steps = []; idle = true
        if let message { self.message = message }
    }
}
