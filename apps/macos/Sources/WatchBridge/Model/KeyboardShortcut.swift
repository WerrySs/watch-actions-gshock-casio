import Foundation

struct KeyboardKey: Decodable, Identifiable, Sendable {
    let id: String
    let label: String
    let row: Int
    let macCode: UInt16
}

struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    var key = "right"
    var control = false
    var alt = false
    var shift = false
    var meta = false
    var repetitions = 1

    var definition: KeyboardKey? {
        guard (1...10).contains(repetitions) else { return nil }
        return RustCore.keyboardKeys.first { $0.id == key }
    }
    var summary: String {
        guard let definition else { return "Configure keyboard shortcut" }
        let modifiers = [(control, "⌃"), (alt, "⌥"), (shift, "⇧"), (meta, "⌘")]
            .filter(\.0).map(\.1).joined(separator: " ")
        return "\(modifiers.isEmpty ? "" : modifiers + " + ")\(definition.label) ×\(repetitions)"
    }
}

enum ActionLayer: String, CaseIterable, Identifiable {
    case normal, alternate
    var id: String { rawValue }
    var title: String { self == .normal ? "Normal" : "Alternate" }
}

enum ActionResolution: Equatable {
    case ignored, switched(ActionLayer), action(WatchAction)
}

/// Runtime only: neither a restart, another watch, nor a favorite inherits an alternate layer.
struct ActionModes {
    private var alternateIDs = Set<String>()
    func layer(for id: String?) -> ActionLayer { id.map { alternateIDs.contains($0) } == true ? .alternate : .normal }
    mutating func reset() { alternateIDs.removeAll() }
    mutating func forget(_ id: String) { alternateIDs.remove(id) }
    mutating func resolve(config: ActionsConfig, id: String, event: WatchButtonEvent, authorized: Bool) -> ActionResolution {
        guard authorized, !id.isEmpty, !id.hasPrefix("manual-"), event != .unknown else { return .ignored }
        if event != .auto, config.switchEvent == event {
            if alternateIDs.remove(id) == nil {
                guard alternateIDs.count < 100 else { return .ignored }
                alternateIDs.insert(id)
            }
            return .switched(layer(for: id))
        }
        return .action(config.action(for: event, layer: layer(for: id)))
    }
}
