import Foundation
import XCTest
@testable import WatchBridge

final class ModelsTests: XCTestCase {
    func testBluetoothNameNormalizesModel() {
        XCTAssertEqual(SavedWatch.modelName(from: "CASIO GW-B5600_HR"), "GW-B5600-HR")
        XCTAssertEqual(SavedWatch.modelName(from: "  CASIO F-91W  "), "F-91W")
    }

    func testOldSavedWatchDecodesWithSecureDefaults() throws {
        let json = """
        {
          "id": "OLD-ID",
          "model": "GW-B5600",
          "displayName": "CASIO GW-B5600",
          "firstSeen": "2026-09-01T10:00:00Z",
          "lastSeen": "2026-09-02T10:00:00Z",
          "connectionCount": 3
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let watch = try decoder.decode(SavedWatch.self, from: Data(json.utf8))
        XCTAssertNil(watch.imageFilename)
        XCTAssertFalse(watch.canRunMacActions)
    }

    func testReminderTitleIsAsciiAndLimited() {
        XCTAssertEqual(Reminder.asciiTitle("Crème brûlée at five"), "Creme brulee at fi")
        XCTAssertLessThanOrEqual(Reminder.asciiTitle(String(repeating: "a", count: 100)).count, 18)
    }

    func testExternalProcessIsStoppedAtItsDeadline() async {
        let clock = ContinuousClock()
        let started = clock.now
        let code = await ActionRunner.process("/bin/sleep", ["5"], timeout: .milliseconds(100))
        XCTAssertNotEqual(code, 0)
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(2))
    }

    func testPersistenceSafetyRejectsSymbolicLinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchbridge-persistence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)

        let regular = root.appendingPathComponent("state.json")
        let symbolicLink = root.appendingPathComponent("linked.json")
        try Data("{}".utf8).write(to: regular)
        try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: regular)

        XCTAssertTrue(Persistence.isSafeRegularFile(regular, maximumBytes: 10))
        XCTAssertFalse(Persistence.isSafeRegularFile(symbolicLink, maximumBytes: 10))
    }

    func testPrivateDirectoryRejectsSymbolicLinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchbridge-directory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target", isDirectory: true)
        let symbolicLink = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: target)

        XCTAssertFalse(Persistence.ensurePrivateDirectory(symbolicLink))
    }

    @MainActor
    func testUnknownImageFilenameIsNotDecodedIntoAPath() throws {
        var watch = SavedWatch(
            id: "TEST",
            model: "F-91W",
            displayName: "CASIO F-91W",
            firstSeen: .now,
            lastSeen: .now,
            connectionCount: 0,
            imageFilename: "../../outside.png"
        )
        XCTAssertEqual(watch.imageFilename, "../../outside.png")
        XCTAssertNil(WatchImageStore.image(named: watch.imageFilename))
        watch.allowsMacActions = true
        XCTAssertFalse(watch.canRunMacActions)
    }

    @MainActor
    func testAllReservedEventsFailClosedThroughFFI() {
        for value in 5...255 {
            var packet = [UInt8](repeating: 0, count: 19)
            packet[0] = 0x10; packet[8] = UInt8(value)
            XCTAssertEqual(RustCore.decodeButton(packet), .unknown)
        }
        XCTAssertFalse(RustCore.supports(bluetoothName: "CASIO F-91W"))
        XCTAssertFalse(RustCore.supports(bluetoothName: "CASIO"))
        XCTAssertTrue(RustCore.supports(bluetoothName: "CASIO GW-B5600"))
    }

    func testPendingChangesNeverCrossPhysicalWatches() throws {
        var queue = PendingQueue()
        queue.enqueue(.timer(60), for: "watch-A")
        queue.enqueue(.timer(120), for: "watch-B")
        queue.acknowledge(.timer(60), for: "watch-B")
        XCTAssertEqual(queue.pending(for: "watch-A"), [.timer(60)])
        XCTAssertEqual(queue.pending(for: "watch-B"), [.timer(120)])
        queue.enqueue(.timer(90), for: "watch-A")
        queue.acknowledge(.timer(60), for: "watch-A")
        XCTAssertEqual(queue.pending(for: "watch-A"), [.timer(90)])
        let restored = try JSONDecoder().decode(PendingQueue.self, from: JSONEncoder().encode(queue))
        XCTAssertEqual(restored.pending(for: "watch-A"), [.timer(90)])
        XCTAssertThrowsError(try JSONDecoder().decode(PendingQueue.self, from: Data("{\"schemaVersion\":999,\"changes\":{}}".utf8)))
    }

    @MainActor
    func testExplicitLinkPreservesReadingsButResetsTrust() throws {
        let store = WatchStore.preview()
        let physical = try XCTUnwrap(store.watches.first(where: { $0.connectionCount > 0 }))
        let manual = try XCTUnwrap(store.watches.first(where: { $0.manuallyRegistered == true }))
        XCTAssertTrue(physical.canRunMacActions)
        store.linkRegistration(manual.id, to: physical.id)
        let linked = try XCTUnwrap(store.watches.first(where: { $0.id == physical.id }))
        XCTAssertFalse(linked.canRunMacActions)
        XCTAssertEqual(linked.lastBattery, physical.lastBattery)
        XCTAssertEqual(linked.effectiveModel, manual.effectiveModel)
        XCTAssertFalse(store.watches.contains(where: { $0.id == manual.id }))
    }

    func testInvalidQueuedValuesAreRejected() throws {
        var queue = PendingQueue()
        queue.enqueue(.timer(-1), for: "watch-A")
        queue.enqueue(.alarm(Alarm(number: 0)), for: "watch-A")
        XCTAssertTrue(queue.pending(for: "watch-A").isEmpty)
    }

    @MainActor
    func testCorruptFilesArePreservedAndWritesArePaused() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: directory)
            PersistenceStatus.shared.failure = nil
        }
        let file = directory.appendingPathComponent("state.json")
        let original = Data("broken JSON".utf8)
        try original.write(to: file)
        XCTAssertNil(Persistence.load([String].self, from: "state.json", in: directory))
        XCTAssertNotNil(PersistenceStatus.shared.failure)
        XCTAssertFalse(Persistence.save(["replacement"], as: "state.json", in: directory))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor
    func testUnsupportedRegistrationIsRejected() {
        let store = WatchStore(bluetooth: false)
        XCTAssertNil(store.registerWatch(model: "F-91W"))
        XCTAssertNotNil(store.registerWatch(model: "GW-B5600BP-1"))
    }
}
