import Foundation

// MARK: - Watch gestures

/// The physical gesture that started a connection, reported in response 0x10.
enum WatchButtonEvent: String, Codable, CaseIterable, Identifiable, Hashable {
    case leftLong = "left_long"
    case rightShort = "right_short"
    case find
    case auto
    case unknown

    var id: String { rawValue }

    /// Gestures the user can configure.
    static let configurable: [WatchButtonEvent] = [.find, .rightShort, .leftLong, .auto]

    var title: String {
        switch self {
        case .leftLong: "Button C, hold for 3 seconds"
        case .rightShort: "Button D, short press"
        case .find: "Button D, hold for 5 seconds"
        case .auto: "Automatic connection"
        case .unknown: "Unknown gesture"
        }
    }

    var display: String {
        switch self {
        case .leftLong: "CNCT"
        case .rightShort: "TIME"
        case .find: "FIND"
        case .auto: "AUTO"
        case .unknown: "?"
        }
    }

    var gesture: String {
        switch self {
        case .leftLong: "Hold the lower-left button for about 3 seconds until CNCT flashes. This is the full read-and-write connection."
        case .rightShort: "Press the lower-right button once. TIME flashes while the Mac sends the current time."
        case .find: "Hold the lower-right button for about 5 seconds until FIND flashes. Keep holding when RCVD appears."
        case .auto: "Supported watches connect around 00:30, 06:30, 12:30, and 18:30 to adjust the time."
        case .unknown: ""
        }
    }

    var position: WatchButtonPosition? {
        switch self {
        case .leftLong: .lowerLeft
        case .rightShort, .find: .lowerRight
        default: nil
        }
    }
}

enum WatchButtonPosition: String, CaseIterable, Identifiable {
    case upperLeft, lowerLeft, upperRight, lowerRight
    var id: String { rawValue }
    var letter: String {
        switch self {
        case .upperLeft: "A"
        case .upperRight: "B"
        case .lowerLeft: "C"
        case .lowerRight: "D"
        }
    }
    var events: [WatchButtonEvent] {
        switch self {
        case .lowerLeft: [.leftLong]
        case .lowerRight: [.rightShort, .find]
        default: []
        }
    }
}

// MARK: - Watch data

/// A physical watch known by the app. CoreBluetooth assigns the UUID, which lets the
/// app distinguish two units of the same model without collecting personal data.
struct SavedWatch: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var model: String
    var displayName: String
    var firstSeen: Date
    var lastSeen: Date
    var connectionCount: Int
    var lastBattery: Int?
    var lastTemperature: Int?
    /// Exact variant selected by the user. `model` always keeps the Bluetooth-detected value.
    var configuredModel: String?
    /// Optional nickname used to distinguish identical units.
    var nickname: String?
    /// `true` when the watch was registered before CoreBluetooth supplied an identifier.
    var manuallyRegistered: Bool?
    /// Random filename for the sanitized PNG in Application Support, never a user-selected path.
    var imageFilename: String?
    /// Mac actions stay blocked until the user explicitly trusts this physical unit.
    var allowsMacActions: Bool?
    /// Last complete snapshot of the known watch state.
    var lastTimeSync: Date?
    var lastHomeCity: String?
    var lastTimerSeconds: Int?
    var lastAlarms: [Alarm]?
    var lastReminders: [Reminder]?
    var lastSettings: WatchSettings?
    var lastAutoTimeAdjust: Bool?
    var lastEvent: WatchButtonEvent?

    var effectiveModel: String { configuredModel ?? model }
    var canRunMacActions: Bool {
        allowsMacActions == true && connectionCount > 0 && manuallyRegistered != true
            && RustCore.supports(model: model)
    }
    var effectiveDisplayName: String { SavedWatch.displayName(for: effectiveModel) }
    var title: String {
        let cleaned = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? effectiveDisplayName : cleaned
    }

    static func modelName(from bluetoothName: String) -> String {
        RustCore.model(fromBluetoothName: bluetoothName)
    }

    static func displayName(for model: String) -> String {
        model.uppercased().hasPrefix("CASIO") ? model : "CASIO \(model)"
    }
}

/// Known model variants. Photography is independent and always supplied by the user.
enum WatchModelVariant: String, CaseIterable, Identifiable {
    case generic = "GW-B5600"
    case blue = "GW-B5600-2"
    case blackComposite = "GW-B5600BC-1B"
    case redComposite = "GW-B5600HR-1"
    case retro = "GW-B5600BL-1"
    case paisley = "GW-B5600BP-1"
    case midnightGreen = "GW-B5600MG-1"

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .generic: "GW-B5600 · black and red"
        case .blue: "GW-B5600-2 · blue"
        case .blackComposite: "GW-B5600BC-1B · black composite"
        case .redComposite: "GW-B5600HR-1 · black and red"
        case .retro: "GW-B5600BL-1 · purple and green"
        case .paisley: "GW-B5600BP-1 · blue paisley"
        case .midnightGreen: "GW-B5600MG-1 · midnight green"
        }
    }

    static func matching(_ model: String) -> WatchModelVariant? {
        var normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.hasPrefix("CASIO ") { normalized.removeFirst("CASIO ".count) }
        guard normalized.contains("GW-B5600") else { return nil }
        return allCases
            .sorted { $0.rawValue.count > $1.rawValue.count }
            .first { normalized.hasPrefix($0.rawValue) } ?? .generic
    }
}

enum RepeatMode: String, Codable, CaseIterable, Identifiable {
    case never = "NEVER", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .never: "Once or date range"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .yearly: "Every year"
        }
    }
    var mask: UInt8 {
        switch self {
        case .never: 0
        case .weekly: 0x04
        case .monthly: 0x10
        case .yearly: 0x08
        }
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable {
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: Int { rawValue }
    static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }
    var short: String { ["M", "T", "W", "T", "F", "S", "S"][rawValue] }
    var name: String { ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][rawValue] }
    var mask: UInt8 {
        switch self {
        case .sunday: 0x01
        case .monday: 0x02
        case .tuesday: 0x04
        case .wednesday: 0x08
        case .thursday: 0x10
        case .friday: 0x20
        case .saturday: 0x40
        }
    }
}

struct Reminder: Codable, Identifiable, Equatable, Hashable {
    var slot: Int
    var title: String = ""
    var enabled: Bool = false
    var repeatMode: RepeatMode = .never
    var start: Date = Calendar.current.startOfDay(for: .now)
    var end: Date = Calendar.current.startOfDay(for: .now)
    var days: Set<Weekday> = []

    var id: Int { slot }
    static let slots = 5
    static var defaults: [Reminder] { (1...slots).map { Reminder(slot: $0) } }

    /// Text exactly as the watch can display it: ASCII, 18 characters.
    var watchTitle: String { Reminder.asciiTitle(title) }

    static func asciiTitle(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        let ascii = folded.unicodeScalars.filter { $0.value >= 0x20 && $0.value <= 0x7E }
        return String(String.UnicodeScalarView(ascii).prefix(18))
    }
}

struct Alarm: Codable, Identifiable, Equatable, Hashable {
    var number: Int
    var hour: Int = 7
    var minute: Int = 0
    var enabled: Bool = false
    var hourlyChime: Bool = false
    var id: Int { number }
    static var defaults: [Alarm] { (1...5).map { Alarm(number: $0) } }
    var timeText: String { String(format: "%02d:%02d", hour, minute) }
}

struct WatchSettings: Codable, Equatable, Hashable {
    var twentyFourHour = true
    var buttonTone = true
    var autoLight = false
    var powerSaving = true
    var longLight = false          // 4 seconds instead of 2
    var dayFirstDate = true        // DD:MM
    var language = 0               // index in WatchSettings.languages
    static let languages = ["English", "Spanish", "French", "German", "Italian", "Russian"]
}

// MARK: - Mac actions

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none, sound, say, shortcut, openApp, url, lockScreen, sleepDisplay, muteToggle, playPause
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Do nothing"
        case .sound: "Find this Mac"
        case .say: "Speak a phrase"
        case .shortcut: "Run a Shortcut"
        case .openApp: "Open an app"
        case .url: "Open a web link"
        case .lockScreen: "Lock the screen"
        case .sleepDisplay: "Turn off the display"
        case .muteToggle: "Toggle mute"
        case .playPause: "Play or pause media"
        }
    }
    var systemImage: String {
        switch self {
        case .none: "circle.dashed"
        case .sound: "speaker.wave.3.fill"
        case .say: "bubble.left.fill"
        case .shortcut: "square.2.layers.3d.fill"
        case .openApp: "app.badge.fill"
        case .url: "link"
        case .lockScreen: "lock.fill"
        case .sleepDisplay: "display"
        case .muteToggle: "speaker.slash.fill"
        case .playPause: "playpause.fill"
        }
    }
    var needsValue: Bool { [.say, .shortcut, .openApp, .url].contains(self) }
    var valuePrompt: String {
        switch self {
        case .say: "Phrase spoken by the Mac"
        case .shortcut: "Exact Shortcut name"
        case .openApp: "App name, for example Music"
        case .url: "https://…"
        default: ""
        }
    }
}

struct WatchAction: Codable, Equatable, Hashable {
    var kind: ActionKind = .none
    var value: String = ""
    static let none = WatchAction()
    var summary: String {
        switch kind {
        case .none: "No action"
        case .say: "Speak “\(value)”"
        case .shortcut: "Shortcut “\(value)”"
        case .openApp: "Open \(value)"
        case .url: "Open \(value)"
        default: kind.label
        }
    }
}

struct ActionsConfig: Codable, Equatable {
    var actions: [WatchButtonEvent: WatchAction] = [
        .find: WatchAction(kind: .sound),
        .rightShort: .none,
        .leftLong: .none,
        .auto: .none,
    ]
    var syncTimeOn: Set<WatchButtonEvent> = [.rightShort, .auto]
    var timeOffsetSeconds: Int = 0

    func action(for event: WatchButtonEvent) -> WatchAction { event == .unknown ? .none : actions[event] ?? .none }
}

// MARK: - Pending changes and history

enum PendingChange: Codable, Equatable, Identifiable {
    case reminder(Reminder)
    case alarm(Alarm)
    case timer(Int)
    case settings(WatchSettings)
    case autoTimeAdjust(Bool)
    case syncTime

    var isValid: Bool {
        switch self {
        case .reminder(let reminder):
            return (1...5).contains(reminder.slot) && reminder.title.utf8.count <= 4096
        case .alarm(let alarm):
            return (1...5).contains(alarm.number) && (0...23).contains(alarm.hour) && (0...59).contains(alarm.minute)
        case .timer(let seconds): return (0...86_399).contains(seconds)
        case .settings(let settings): return WatchSettings.languages.indices.contains(settings.language)
        case .autoTimeAdjust, .syncTime: return true
        }
    }

    var id: String {
        switch self {
        case .reminder(let r): "reminder-\(r.slot)"
        case .alarm(let a): "alarm-\(a.number)"
        case .timer: "timer"
        case .settings: "settings"
        case .autoTimeAdjust: "autoTimeAdjust"
        case .syncTime: "syncTime"
        }
    }

    var summary: String {
        switch self {
        case .reminder(let r): "Reminder \(r.slot): \(r.watchTitle.isEmpty ? "empty" : r.watchTitle)"
        case .alarm(let a): "Alarm \(a.number): \(a.timeText)\(a.enabled ? "" : " (off)")"
        case .timer(let s): "Timer: \(Formatters.duration(s))"
        case .settings: "Watch settings"
        case .autoTimeAdjust(let on): on ? "Enable automatic time adjustment" : "Disable automatic time adjustment"
        case .syncTime: "Set the current time"
        }
    }
}

struct LogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date = .now
    var event: WatchButtonEvent = .unknown
    var battery: Int?
    var temperature: Int?
    var timeSynced = false
    var applied: [String] = []
    var error: String?
    var watchID: String?
    var watchModel: String?
}

enum Formatters {
    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    static let dateTime: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d, HH:mm"; return f
    }()
    static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d, yy"; return f
    }()
}
