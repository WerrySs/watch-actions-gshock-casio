import AppKit
import ApplicationServices
import AVFoundation
import Darwin
import Foundation

/// Runs the Mac action assigned to a watch gesture and returns a privacy-safe trace line.
enum ActionRunner {
    @discardableResult
    static func run(_ action: WatchAction) async -> String {
        switch action.kind {
        case .none:
            return "no action"
        case .keyboard:
            return await KeyboardEmitter.run(action.keyboard)
        case .sound:
            return await playAlert()
        case .say:
            _ = await speak(action.value.isEmpty ? "Here I am" : action.value)
            return "speech played"
        case .shortcut:
            let code = await process("/usr/bin/shortcuts", ["run", action.value])
            return "shortcut → code \(code)"
        case .openApp:
            let code = await process("/usr/bin/open", ["-a", action.value])
            return "open app → code \(code)"
        case .url:
            guard let url = URL(string: action.value),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else {
                return "blocked link: only HTTP and HTTPS addresses are allowed"
            }
            let ok = await MainActor.run { NSWorkspace.shared.open(url) }
            return "open link → \(ok ? "ok" : "failed")"
        case .lockScreen:
            let code = await process("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", ["-suspend"])
            if code == 0 { return "screen lock requested" }
            // CGSession is absent on newer macOS. Never substitute display sleep for a lock
            // or change system permissions: this optional shortcut needs user authorization.
            guard AXIsProcessTrusted() else {
                return "screen lock needs Accessibility permission for WatchBridge; use Control-Command-Q manually"
            }
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0x0C, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0x0C, keyDown: false) else {
                return "could not create the screen-lock request"
            }
            down.flags = [.maskControl, .maskCommand]
            up.flags = [.maskControl, .maskCommand]
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            return "screen-lock shortcut requested; verify the screen is locked"
        case .sleepDisplay:
            let code = await process("/usr/bin/pmset", ["displaysleepnow"])
            return "turn off display → code \(code)"
        case .muteToggle:
            let code = await process("/usr/bin/osascript", ["-e", "set volume output muted not (output muted of (get volume settings))"])
            return "toggle mute → code \(code)"
        case .playPause:
            let code = await process("/usr/bin/osascript", ["-e", "tell application \"Music\" to playpause"])
            return "play or pause → code \(code)"
        }
    }

    /// Draws attention, plays three alerts, and speaks to help locate the Mac.
    static func playAlert() async -> String {
        _ = await MainActor.run { NSApplication.shared.requestUserAttention(.criticalRequest) }
        for _ in 0..<3 {
            await process("/usr/bin/afplay", ["-v", "3", "/System/Library/Sounds/Glass.aiff"])
        }
        return "alert + " + (await speak("Here I am"))
    }

    @MainActor private static let synthesizer = AVSpeechSynthesizer()

    /// Uses the most reliable speech path: `say` writes a temporary audio file and `afplay`
    /// plays it. AVSpeechSynthesizer is the fallback when that path is unavailable.
    static func speak(_ text: String) async -> String {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchbridge-speech-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: file) }
        let code = await process("/usr/bin/say", ["-o", file.path, text])
        if code == 0, FileManager.default.fileExists(atPath: file.path) {
            let play = await process("/usr/bin/afplay", ["-v", "2", file.path])
            return "speech “\(text)” via say+afplay → code \(play)"
        }
        await MainActor.run {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            synthesizer.speak(utterance)
        }
        return "speech “\(text)” via AVSpeech (`say` failed with code \(code))"
    }

    @discardableResult
    static func process(_ path: String, _ arguments: [String], timeout: Duration = .seconds(60)) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        let processID = process.processIdentifier
        let hasOwnProcessGroup = Darwin.setpgid(processID, processID) == 0

        return await withTaskGroup(of: Int32.self) { group in
            group.addTask {
                process.waitUntilExit()
                return process.terminationStatus
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return process.terminationStatus
                }
                if process.isRunning {
                    Darwin.kill(hasOwnProcessGroup ? -processID : processID, SIGKILL)
                }
                return -2
            }
            let result = await group.next() ?? -1
            group.cancelAll()
            return result
        }
    }
}
