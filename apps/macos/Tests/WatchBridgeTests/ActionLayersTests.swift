import Foundation
import XCTest
@testable import WatchBridge

final class ActionLayersTests: XCTestCase {
    func testOldConfigurationPreservesItsActions() throws {
        var config = ActionsConfig()
        config.actions[.rightShort] = WatchAction(kind: .say, value: "Original action")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        old.removeValue(forKey: "alternateActions")
        old.removeValue(forKey: "profiles")
        old.removeValue(forKey: "schemaVersion")
        old.removeValue(forKey: "switchEvent")
        let restored = try JSONDecoder().decode(ActionsConfig.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(restored.actions, config.actions)
        XCTAssertEqual(restored.syncTimeOn, config.syncTimeOn)
        XCTAssertTrue(restored.profiles[0].actions.isEmpty)
        XCTAssertNil(restored.switchEvent)
    }

    func testTwoLayersRoundTripAndBackgroundAlwaysUsesNormal() throws {
        var config = ActionsConfig()
        config.switchEvent = .find
        config.actions[.auto] = WatchAction(kind: .say, value: "Normal")
        config.profiles[0].actions[.auto] = WatchAction(kind: .say, value: "Must not run")
        config.profiles[0].actions[.rightShort] = WatchAction(kind: .keyboard, keyboard: KeyboardShortcut(repetitions: 2))
        let restored = try JSONDecoder().decode(ActionsConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored, config)
        XCTAssertEqual(restored.action(for: .auto, layer: .profile(1)), config.actions[.auto])
        XCTAssertEqual(restored.action(for: .unknown, layer: .profile(1)), .none)
    }

    func testModeSwitchIsIsolatedTrustedAndReversible() {
        var config = ActionsConfig()
        config.switchEvent = .find
        config.profiles[0].actions[.rightShort] = WatchAction(kind: .keyboard, keyboard: KeyboardShortcut(repetitions: 2))
        var modes = ActionModes()
        XCTAssertEqual(modes.resolve(config: config, id: "A", event: .find, authorized: false), .ignored)
        XCTAssertEqual(modes.resolve(config: config, id: "A", event: .find, authorized: true), .switched(.profile(1)))
        XCTAssertEqual(modes.layer(for: "B"), .normal)
        XCTAssertEqual(modes.resolve(config: config, id: "A", event: .rightShort, authorized: true), .action(config.profiles[0].actions[.rightShort]!))
        XCTAssertEqual(modes.resolve(config: config, id: "A", event: .find, authorized: true), .switched(.normal))
        _ = modes.resolve(config: config, id: "B", event: .find, authorized: true)
        modes.forget("B")
        XCTAssertEqual(modes.layer(for: "B"), .normal)
        _ = modes.resolve(config: config, id: "A", event: .find, authorized: true)
        modes.reset()
        XCTAssertEqual(modes.layer(for: "A"), .normal)
    }

    func testAutomaticUnknownAndManualCannotSwitchModes() {
        var config = ActionsConfig(); config.switchEvent = .auto
        var modes = ActionModes()
        _ = modes.resolve(config: config, id: "A", event: .auto, authorized: true)
        XCTAssertEqual(modes.layer(for: "A"), .normal)
        XCTAssertEqual(modes.resolve(config: config, id: "A", event: .unknown, authorized: true), .ignored)
        XCTAssertEqual(modes.resolve(config: config, id: "manual-A", event: .find, authorized: true), .ignored)
    }

    func testSharedKeyboardCatalogAndBalancedModifierRelease() throws {
        XCTAssertGreaterThan(RustCore.keyboardKeys.count, 70)
        XCTAssertEqual(Set(RustCore.keyboardKeys.map(\.id)).count, RustCore.keyboardKeys.count)
        let shortcut = KeyboardShortcut(control: true, alt: true, shift: true, meta: true, repetitions: 2)
        let plan = try XCTUnwrap(KeyboardEmitter.plan(shortcut))
        XCTAssertEqual(plan.count, 20) // Two complete ten-event chords.
        XCTAssertEqual(plan.filter(\.down).map(\.code), plan.filter { !$0.down }.map(\.code).reversed())
        XCTAssertEqual(plan.last?.flags.rawValue, 0)
        XCTAssertEqual(plan[4].code, 124) // Right arrow, from the shared Rust catalog.
        XCTAssertEqual(shortcut.summary, "⌃ ⌥ ⇧ ⌘ + → ×2")
    }

    func testInvalidKeyboardRequestsAreNotPlanned() {
        for repeats in [0, 11, 1000] { XCTAssertNil(KeyboardEmitter.plan(KeyboardShortcut(repetitions: repeats))) }
        XCTAssertNil(KeyboardEmitter.plan(KeyboardShortcut(key: "unknown")))
    }

    func testDoubleCommandRecordsAndReplaysTwoModifierTaps() throws {
        let events: [RustCore.RecordedEvent] = [.init(key: "meta", down: true, time_ms: 0), .init(key: "meta", down: false, time_ms: 40), .init(key: "meta", down: true, time_ms: 180), .init(key: "meta", down: false, time_ms: 220)]
        let recording = try XCTUnwrap(RustCore.recordKeys(events))
        XCTAssertNil(recording.error); XCTAssertTrue(recording.idle)
        let shortcut = KeyboardShortcut.recorded(recording.steps)
        XCTAssertTrue(shortcut.isValid); XCTAssertNil(shortcut.definition) // Old key pickers cannot reinterpret a sequence.
        XCTAssertEqual(shortcut.summary, "⌘ → ⌘")
        XCTAssertEqual(shortcut.steps?.last?.delayMs, 140)
        let plan = try XCTUnwrap(KeyboardEmitter.plan(shortcut))
        XCTAssertEqual(plan.map(\.code), [55, 55, 55, 55])
        XCTAssertEqual(plan.map(\.down), [true, false, true, false])
        XCTAssertTrue(plan.allSatisfy(\.modifier))
        XCTAssertEqual(plan.map(\.flags.rawValue), [1 << 20, 0, 1 << 20, 0])
        XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcut.self, from: JSONEncoder().encode(shortcut)), shortcut)
    }

    func testRecordingFFIBoundsAndIncompleteChords() throws {
        let incomplete = try XCTUnwrap(RustCore.recordKeys([.init(key: "meta", down: true, time_ms: 0)]))
        XCTAssertFalse(incomplete.idle); XCTAssertTrue(incomplete.steps.isEmpty)
        XCTAssertNotNil(RustCore.recordKeys([.init(key: "unsupported", down: true, time_ms: 0)])?.error)
        XCTAssertFalse(KeyboardShortcut.recorded([]).isValid)
        XCTAssertFalse(KeyboardShortcut.recorded(Array(repeating: .init(key: "meta"), count: 33)).isValid)
        XCTAssertFalse(KeyboardShortcut.recorded([.init(key: "meta", modifiers: 8)]).isValid)
        XCTAssertFalse(KeyboardShortcut.recorded([.init(key: "meta", delayMs: 100)]).isValid)
        let shortcut = KeyboardShortcut.recorded([.init(key: "right_meta"), .init(key: "c", modifiers: 8, delayMs: 100)])
        XCTAssertTrue(shortcut.isValid)
        XCTAssertEqual(KeyboardEmitter.plan(shortcut)?.last?.flags.rawValue, 0)
    }

    func testNamedModesCycleInOrderAndRemainIsolated() throws {
        var config = ActionsConfig(); config.switchEvent = .find
        let music = try XCTUnwrap(config.addProfile(named: "Music"))
        let presentation = try XCTUnwrap(config.addProfile(named: "Presentation"))
        config.profiles[1].color = "green"
        config.profiles[1].actions[.rightShort] = WatchAction(kind: .playPause)
        var modes = ActionModes()
        for expected in [ActionLayer.profile(1), music, presentation, .normal] {
            XCTAssertEqual(modes.resolve(config: config, id: "A", event: .find, authorized: true), .switched(expected))
            XCTAssertEqual(modes.layer(for: "B"), .normal)
            XCTAssertEqual(modes.resolve(config: config, id: "A", event: .auto, authorized: true), .action(config.actions[.auto]!))
        }
        let restored = try JSONDecoder().decode(ActionsConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored, config); XCTAssertEqual(restored.name(for: music), "Music"); XCTAssertEqual(restored.color(for: music), "green")
        config.profiles.swapAt(0, 2)
        XCTAssertEqual(config.nextLayer(after: .normal), presentation)
        XCTAssertEqual(config.action(for: .rightShort, layer: music).kind, .playPause)
        config.profiles.removeAll { $0.id == music.id }
        XCTAssertEqual(config.action(for: .rightShort, layer: music), .none)
        XCTAssertEqual(config.nextLayer(after: music), .normal)
    }

    func testLegacyAlternateActionsMigrateWithoutLosingBindings() throws {
        var config = ActionsConfig(); config.switchEvent = .leftLong
        config.profiles[0].actions[.rightShort] = WatchAction(kind: .say, value: "Keep me")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        let profiles = try XCTUnwrap(json.removeValue(forKey: "profiles") as? [[String: Any]])
        json["alternateActions"] = profiles[0]["actions"]
        json.removeValue(forKey: "schemaVersion")
        let restored = try JSONDecoder().decode(ActionsConfig.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.profiles, config.profiles); XCTAssertEqual(restored.switchEvent, .leftLong)
        json["schemaVersion"] = 999
        XCTAssertThrowsError(try JSONDecoder().decode(ActionsConfig.self, from: JSONSerialization.data(withJSONObject: json)))
    }

    @MainActor func testModeIndicatorStaysInsideUsableScreenBounds() {
        for visible in [CGRect(x: 0, y: 0, width: 1440, height: 875), CGRect(x: -1920, y: 100, width: 1920, height: 1000), CGRect(x: 0, y: 0, width: 320, height: 480)] {
            let frame = ModeIndicatorController.frame(in: visible)
            XCTAssertTrue(visible.contains(frame)); XCTAssertEqual(frame.midX, visible.midX)
            XCTAssertEqual(frame.maxY, visible.maxY - 8)
        }
    }

    @MainActor func testModeManagementRetainsOtherActions() {
        let store = WatchStore.preview(connected: false)
        let original = store.config.actions
        store.addMode(named: "Music")
        let music = store.editingLayer
        store.setAction(WatchAction(kind: .playPause), for: .rightShort, layer: music)
        store.updateMode(music, name: "Media", color: "green")
        store.moveMode(music, by: -1)
        XCTAssertEqual(store.config.name(for: music), "Media")
        XCTAssertEqual(store.config.color(for: music), "green")
        XCTAssertEqual(store.config.action(for: .rightShort, layer: music).kind, .playPause)
        store.deleteMode(music)
        XCTAssertEqual(store.editingLayer, .normal)
        XCTAssertEqual(store.config.actions, original)
        store.setAction(WatchAction(kind: .lockScreen), for: .rightShort, layer: music)
        XCTAssertEqual(store.config.actions, original) // Stale editors cannot write into Normal.
    }
}
