import Foundation

/// Queues belong to physical units, never to model names or the Dashboard favorite.
struct PendingQueue: Codable {
    var schemaVersion = 2
    var changes: [String: [PendingChange]] = [:]

    init() {}
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container, debugDescription: "Unsupported queue version")
        }
        changes = try container.decode([String: [PendingChange]].self, forKey: .changes)
        guard changes.count <= 100, changes.values.allSatisfy({ $0.count <= 32 && $0.allSatisfy(\.isValid) }) else {
            throw DecodingError.dataCorruptedError(forKey: .changes, in: container, debugDescription: "Queue exceeds safety limits")
        }
    }
    func pending(for id: String?) -> [PendingChange] { id.flatMap { changes[$0] } ?? [] }
    mutating func enqueue(_ change: PendingChange, for id: String) {
        guard change.isValid else { return }
        var queue = pending(for: id).filter { $0.id != change.id }
        guard queue.count < 32 else { return }
        queue.append(change)
        changes[id] = queue
    }
    mutating func acknowledge(_ change: PendingChange, for id: String) {
        changes[id]?.removeAll { $0 == change }
    }
}
