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
            imageFilename: "../../archivo.png"
        )
        XCTAssertEqual(watch.imageFilename, "../../archivo.png")
        XCTAssertNil(WatchImageStore.image(named: watch.imageFilename))
        watch.allowsMacActions = true
        XCTAssertTrue(watch.canRunMacActions)
    }
}
