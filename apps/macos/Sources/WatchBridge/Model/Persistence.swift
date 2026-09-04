import Foundation

/// Local files under Application Support/WatchBridge. The directory and files are private
/// to the current user because they can contain reminder titles and configured actions.
enum Persistence {
    private static let maximumFileBytes = 10_000_000

    static let directory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchBridge", isDirectory: true)
    }()

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard ensurePrivateDirectory(directory),
              let url = url(for: name),
              isSafeRegularFile(url, maximumBytes: maximumFileBytes),
              let data = try? Data(contentsOf: url),
              data.count <= maximumFileBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, as name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              data.count <= maximumFileBytes,
              ensurePrivateDirectory(directory),
              let url = url(for: name),
              isSafeWriteTarget(url) else { return }
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            assertionFailure("Could not save \(name): \(error)")
        }
    }

    static func remove(_ name: String) {
        guard ensurePrivateDirectory(directory),
              let url = url(for: name),
              isSafeRegularFile(url, maximumBytes: maximumFileBytes) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func ensurePrivateDirectory(_ url: URL) -> Bool {
        let manager = FileManager.default
        do {
            if manager.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { return false }
            } else {
                try manager.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    static func isSafeRegularFile(_ url: URL, maximumBytes: Int) -> Bool {
        guard maximumBytes >= 0,
              let values = try? url.resourceValues(
                  forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size >= 0,
              size <= maximumBytes else { return false }
        return true
    }

    private static func isSafeWriteTarget(_ url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values.isRegularFile == true && values.isSymbolicLink != true
        } catch CocoaError.fileReadNoSuchFile {
            return true
        } catch {
            return false
        }
    }

    private static func url(for name: String) -> URL? {
        guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        return directory.appendingPathComponent(name, isDirectory: false)
    }
}

/// Asynchronous lock that permits only one Bluetooth operation at a time.
@MainActor
final class AsyncLock {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(_ body: () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async {
        if !locked { locked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
    }
}
