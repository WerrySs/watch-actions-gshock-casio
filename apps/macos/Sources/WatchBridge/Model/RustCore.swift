import CWatchBridge
import Foundation

/// Small, ownership-safe bridge to the shared Rust protocol and validation engine.
enum RustCore {
    static let keyboardKeys: [KeyboardKey] = {
        guard let pointer = wb_keyboard_catalog_json() else { return [] }
        defer { wb_string_free(pointer) }
        return (try? JSONDecoder().decode([KeyboardKey].self, from: Data(String(cString: pointer).utf8))) ?? []
    }()

    static var version: String {
        guard let pointer = wb_core_version() else { return "unknown" }
        return String(cString: pointer)
    }

    static func normalizeModel(_ value: String) -> String {
        ownedString(value, using: wb_normalize_model)
    }

    static func supports(model: String) -> Bool {
        model.withCString { wb_is_supported_model($0) }
    }

    static func supports(bluetoothName: String) -> Bool {
        bluetoothName.withCString { wb_is_supported_bluetooth_name($0) }
    }

    static func model(fromBluetoothName value: String) -> String {
        ownedString(value, using: wb_model_from_bluetooth_name)
    }

    static func sanitize(_ value: String, limit: Int) -> String {
        value.withCString { input in
            guard let output = wb_sanitize_text(input, max(0, limit)) else { return "" }
            defer { wb_string_free(output) }
            return String(cString: output)
        }
    }

    static func decodeButton(_ bytes: [UInt8]) -> WatchButtonEvent {
        let code = bytes.withUnsafeBufferPointer { buffer in
            wb_decode_button(buffer.baseAddress, buffer.count)
        }
        return switch code {
        case 0: WatchButtonEvent.leftLong
        case 1: WatchButtonEvent.rightShort
        case 2: WatchButtonEvent.find
        case 3: WatchButtonEvent.auto
        default: WatchButtonEvent.unknown
        }
    }

    static func decodeCondition(_ bytes: [UInt8]) -> (battery: Int, temperature: Int)? {
        var battery: UInt8 = 0
        var temperature: Int16 = 0
        let valid = bytes.withUnsafeBufferPointer { buffer in
            wb_decode_condition(buffer.baseAddress, buffer.count, &battery, &temperature)
        }
        return valid ? (Int(battery), Int(temperature)) : nil
    }

    static func encodeTime(_ date: Date, offsetSeconds: Int = 0) -> [UInt8] {
        let output = wb_encode_time(
            Int64(date.timeIntervalSince1970),
            Int32(clamping: offsetSeconds)
        )
        guard let data = output.data, output.len > 0 else { return [] }
        defer { wb_bytes_free(output) }
        return Array(UnsafeBufferPointer(start: data, count: output.len))
    }

    private static func ownedString(
        _ value: String,
        using operation: (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    ) -> String {
        value.withCString { input in
            guard let output = operation(input) else { return "" }
            defer { wb_string_free(output) }
            return String(cString: output)
        }
    }
}
