import Foundation

struct KeyboardKey: Decodable, Identifiable, Sendable {
    let id: String
    let label: String
    let row: Int
    let macCode: UInt16
    var modifier: Int {
        switch id { case "control", "right_control": 1; case "alt", "right_alt": 2
        case "shift", "right_shift": 4; case "meta", "right_meta": 8; default: 0 }
    }
    var display: String {
        switch id { case "meta": "⌘"; case "right_meta": "Right ⌘"; case "alt": "⌥"; case "right_alt": "Right ⌥"
        case "control": "⌃"; case "right_control": "Right ⌃"; case "shift": "⇧"; case "right_shift": "Right ⇧"; default: label }
    }
}

struct KeyboardStep: Codable, Equatable, Hashable, Sendable {
    var key: String
    var modifiers: Int = 0
    var delayMs: Int = 0
    private enum CodingKeys: String, CodingKey { case key, modifiers; case delayMs = "delay_ms" }
    var definition: KeyboardKey? {
        guard (0...15).contains(modifiers), (0...2000).contains(delayMs),
              let key = RustCore.keyboardKeys.first(where: { $0.id == key }), key.modifier & modifiers == 0 else { return nil }
        return key
    }
    var summary: String {
        guard let definition else { return "Invalid key" }
        return ([(1, "⌃"), (2, "⌥"), (4, "⇧"), (8, "⌘")].filter { modifiers & $0.0 != 0 }.map(\.1) + [definition.display]).joined(separator: " + ")
    }
}

struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    var key = "right"
    var control = false
    var alt = false
    var shift = false
    var meta = false
    var repetitions = 1
    var sequence: [KeyboardStep]?

    var definition: KeyboardKey? {
        guard sequence == nil, (1...10).contains(repetitions) else { return nil }
        return KeyboardStep(key: key, modifiers: modifierBits).definition
    }
    var modifierBits: Int { (control ? 1 : 0) | (alt ? 2 : 0) | (shift ? 4 : 0) | (meta ? 8 : 0) }
    var steps: [KeyboardStep]? {
        if let sequence {
            guard key == "recorded_sequence", repetitions == 1, modifierBits == 0,
                  (1...32).contains(sequence.count), sequence.first?.delayMs == 0,
                  sequence.dropFirst().allSatisfy({ $0.delayMs >= 40 }),
                  sequence.allSatisfy({ $0.definition != nil }), sequence.reduce(0, { $0 + $1.delayMs }) <= 30_000 else { return nil }
            return sequence
        }
        guard definition != nil else { return nil }
        return (0..<repetitions).map { KeyboardStep(key: key, modifiers: modifierBits, delayMs: $0 == 0 ? 0 : 100) }
    }
    var isValid: Bool { steps != nil }
    static func recorded(_ steps: [KeyboardStep]) -> Self { Self(key: "recorded_sequence", sequence: steps) }
    var summary: String {
        if sequence != nil { return steps?.map(\.summary).joined(separator: " → ") ?? "Record a shortcut" }
        guard let definition else { return "Configure keyboard shortcut" }
        let modifiers = [(control, "⌃"), (alt, "⌥"), (shift, "⇧"), (meta, "⌘")]
            .filter(\.0).map(\.1).joined(separator: " ")
        return "\(modifiers.isEmpty ? "" : modifiers + " + ")\(definition.display) ×\(repetitions)"
    }
}

enum ActionLayer: Hashable, Identifiable {
    case normal, profile(Int)
    var id: Int { if case .profile(let id) = self { id } else { 0 } }
}

enum ActionResolution: Equatable {
    case ignored, switched(ActionLayer), action(WatchAction)
}

/// Runtime only: neither a restart, another watch, nor a favorite inherits an alternate layer.
struct ActionModes {
    private var active: [String: ActionLayer] = [:]
    func layer(for id: String?) -> ActionLayer { id.flatMap { active[$0] } ?? .normal }
    mutating func reset() { active.removeAll() }
    mutating func forget(_ id: String) { active.removeValue(forKey: id) }
    mutating func resolve(config: ActionsConfig, id: String, event: WatchButtonEvent, authorized: Bool) -> ActionResolution {
        guard authorized, !id.isEmpty, !id.hasPrefix("manual-"), event != .unknown else { return .ignored }
        if event != .auto, config.switchEvent == event {
            let next = config.nextLayer(after: layer(for: id))
            if next == .normal { active.removeValue(forKey: id) }
            else {
                guard active[id] != nil || active.count < 100 else { return .ignored }
                active[id] = next
            }
            return .switched(next)
        }
        return .action(config.action(for: event, layer: layer(for: id)))
    }
}
