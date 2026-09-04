import Foundation

/// Compatibility protocol command codes (the first byte of each frame).
enum WatchCode {
    static let currentTime: UInt8 = 0x09
    static let bleFeatures: UInt8 = 0x10
    static let timeAdjustment: UInt8 = 0x11
    static let basicSettings: UInt8 = 0x13
    static let alarm1: UInt8 = 0x15
    static let alarms2to5: UInt8 = 0x16
    static let timer: UInt8 = 0x18
    static let dstWatchState: UInt8 = 0x1D
    static let dstSetting: UInt8 = 0x1E
    static let worldCities: UInt8 = 0x1F
    static let appInfo: UInt8 = 0x22
    static let watchName: UInt8 = 0x23
    static let condition: UInt8 = 0x28
    static let reminderTitle: UInt8 = 0x30
    static let reminderTime: UInt8 = 0x31
}

/// Pure frame encoders and decoders. Time and connection decoding delegate to the Rust core.
enum WatchProtocol {

    // MARK: Connection

    static func decodeButton(_ d: [UInt8]) -> WatchButtonEvent {
        RustCore.decodeButton(d)
    }

    /// The watch challenges the client with 0x22 FF×10 00 and expects this fixed response.
    static func isAppInfoChallenge(_ d: [UInt8]) -> Bool {
        d.count >= 12 && d[0] == WatchCode.appInfo && d[1...10].allSatisfy { $0 == 0xFF } && d[11] == 0x00
    }
    static let appInfoResponse: [UInt8] = [0x22, 0x34, 0x88, 0xF4, 0xE5, 0xD5, 0xAF, 0xC8, 0x29, 0xE0, 0x6D, 0x02]

    static func decodeName(_ d: [UInt8]) -> String { ascii(d.dropFirst(1)) }

    static func decodeCondition(_ d: [UInt8]) -> (battery: Int, temperature: Int)? {
        RustCore.decodeCondition(d)
    }

    /// Home city: response to 1F 00, with the ASCII name beginning at byte 2.
    static func decodeCity(_ d: [UInt8]) -> String { ascii(d.dropFirst(2)) }

    // MARK: Time

    static func encodeTime(_ date: Date, calendar: Calendar = .current) -> [UInt8] {
        _ = calendar
        return RustCore.encodeTime(date)
    }

    // MARK: Automatic time adjustment (0x11)

    static func decodeAutoTimeAdjust(_ d: [UInt8]) -> Bool? {
        guard d.count >= 14, d[0] == WatchCode.timeAdjustment else { return nil }
        return d[12] == 0x00
    }
    static func encodeAutoTimeAdjust(original: [UInt8], enabled: Bool, minutesAfterHour: UInt8 = 30) -> [UInt8] {
        var out = original
        guard out.count >= 14 else { return out }
        out[12] = enabled ? 0x00 : 0x80
        out[13] = minutesAfterHour
        return out
    }

    // MARK: Alarms

    private static let alarmEnabled: UInt8 = 0x40
    private static let alarmChime: UInt8 = 0x80
    private static let alarmConstant: UInt8 = 0x40

    static func decodeAlarms(first: [UInt8], rest: [UInt8]) -> [Alarm]? {
        guard first.count >= 5, first[0] == WatchCode.alarm1, rest.count >= 17, rest[0] == WatchCode.alarms2to5 else { return nil }
        func alarm(_ number: Int, _ b: ArraySlice<UInt8>) -> Alarm {
            let a = Array(b)
            return Alarm(number: number, hour: Int(a[2]), minute: Int(a[3]),
                         enabled: a[0] & alarmEnabled != 0, hourlyChime: a[0] & alarmChime != 0)
        }
        var alarms = [alarm(1, first[1...4])]
        for i in 0..<4 {
            let start = 1 + i * 4
            alarms.append(alarm(i + 2, rest[start...(start + 3)]))
        }
        return alarms
    }

    static func encodeAlarms(_ alarms: [Alarm]) -> (first: [UInt8], rest: [UInt8]) {
        func flag(_ a: Alarm) -> UInt8 { (a.enabled ? alarmEnabled : 0) | (a.hourlyChime ? alarmChime : 0) }
        let sorted = alarms.sorted { $0.number < $1.number }
        let first: [UInt8] = [WatchCode.alarm1, flag(sorted[0]), alarmConstant, UInt8(sorted[0].hour), UInt8(sorted[0].minute)]
        var rest: [UInt8] = [WatchCode.alarms2to5]
        for a in sorted.dropFirst() { rest += [flag(a), alarmConstant, UInt8(a.hour), UInt8(a.minute)] }
        return (first, rest)
    }

    // MARK: Timer

    static func decodeTimer(_ d: [UInt8]) -> Int? {
        guard d.count >= 4, d[0] == WatchCode.timer else { return nil }
        return Int(d[1]) * 3600 + Int(d[2]) * 60 + Int(d[3])
    }
    static func encodeTimer(_ seconds: Int) -> [UInt8] {
        [WatchCode.timer, UInt8(seconds / 3600), UInt8((seconds % 3600) / 60), UInt8(seconds % 60), 0, 0]
    }

    // MARK: Basic settings (0x13, 12 bytes)

    static func decodeSettings(_ d: [UInt8]) -> WatchSettings? {
        guard d.count >= 6, d[0] == WatchCode.basicSettings else { return nil }
        var s = WatchSettings()
        s.twentyFourHour = d[1] & 0x01 != 0
        s.buttonTone = d[1] & 0x02 == 0
        s.autoLight = d[1] & 0x04 == 0
        s.powerSaving = d[1] & 0x10 == 0
        s.longLight = d[2] == 1
        s.dayFirstDate = d[4] == 1
        s.language = Int(d[5]) < WatchSettings.languages.count ? Int(d[5]) : 0
        return s
    }
    static func encodeSettings(_ s: WatchSettings) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 12)
        out[0] = WatchCode.basicSettings
        if s.twentyFourHour { out[1] |= 0x01 }
        if !s.buttonTone { out[1] |= 0x02 }
        if !s.autoLight { out[1] |= 0x04 }
        if !s.powerSaving { out[1] |= 0x10 }
        out[2] = s.longLight ? 1 : 0
        out[4] = s.dayFirstDate ? 1 : 0
        out[5] = UInt8(s.language)
        return out
    }

    // MARK: Reminders (0x30 title, 0x31 date)

    static func encodeReminderTitle(_ r: Reminder) -> [UInt8] {
        var bytes = Array(r.watchTitle.utf8.prefix(18))
        bytes += [UInt8](repeating: 0, count: 18 - bytes.count)
        return [WatchCode.reminderTitle, UInt8(r.slot)] + bytes
    }

    static func encodeReminderTime(_ r: Reminder, calendar: Calendar = .current) -> [UInt8] {
        var period: UInt8 = r.enabled ? 0x01 : 0x00
        period |= r.repeatMode.mask
        let s = calendar.dateComponents([.year, .month, .day], from: r.start)
        let e = calendar.dateComponents([.year, .month, .day], from: max(r.end, r.start))
        var dow: UInt8 = 0
        if r.repeatMode == .weekly { for d in r.days { dow |= d.mask } }
        return [WatchCode.reminderTime, UInt8(r.slot), period,
                bcd((s.year ?? 2000) % 100), bcd(s.month ?? 1), bcd(s.day ?? 1),
                bcd((e.year ?? 2000) % 100), bcd(e.month ?? 1), bcd(e.day ?? 1),
                dow, 0]
    }

    /// Returns nil when the slot is empty (0xFF).
    static func decodeReminderTitle(_ d: [UInt8]) -> String? {
        guard d.count >= 3, d[0] == WatchCode.reminderTitle, d[2] != 0xFF else { return nil }
        return ascii(d.dropFirst(2))
    }

    static func decodeReminderTime(_ d: [UInt8], into r: inout Reminder, calendar: Calendar = .current) -> Bool {
        guard d.count >= 10, d[0] == WatchCode.reminderTime, d[3] != 0xFF else { return false }
        let period = d[2]
        r.enabled = period & 0x01 != 0
        if period & 0x04 != 0 { r.repeatMode = .weekly }
        else if period & 0x10 != 0 { r.repeatMode = .monthly }
        else if period & 0x08 != 0 { r.repeatMode = .yearly }
        else { r.repeatMode = .never }
        r.start = date(year: 2000 + unbcd(d[3]), month: unbcd(d[4]), day: unbcd(d[5]), calendar) ?? r.start
        r.end = date(year: 2000 + unbcd(d[6]), month: unbcd(d[7]), day: unbcd(d[8]), calendar) ?? r.start
        let dow = d[9]
        r.days = Set(Weekday.allCases.filter { dow & $0.mask != 0 })
        return true
    }

    // MARK: Utilities

    static func bcd(_ n: Int) -> UInt8 { UInt8(((n / 10) << 4) | (n % 10)) }
    static func unbcd(_ b: UInt8) -> Int { Int(b >> 4) * 10 + Int(b & 0x0F) }

    static func date(year: Int, month: Int, day: Int, _ calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func ascii<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        var out = ""
        for b in bytes {
            if b == 0 { break }
            if b >= 0x20 && b <= 0x7E { out.append(Character(UnicodeScalar(b))) }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
}
