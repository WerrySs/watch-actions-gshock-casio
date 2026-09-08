import Foundation
import XCTest
@testable import WatchBridge

final class ActionLayersTests: XCTestCase {
    func testOldConfigurationPreservesItsActions() throws {
        var config = ActionsConfig()
        config.actions[.rightShort] = WatchAction(kind: .say, value: "Original action")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        old.removeValue(forKey: "alternateActions")
        old.removeValue(forKey: "switchEvent")
        let restored = try JSONDecoder().decode(ActionsConfig.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(restored.actions, config.actions)
        XCTAssertEqual(restored.syncTimeOn, config.syncTimeOn)
        XCTAssertTrue(restored.alternateActions.isEmpty)
        XCTAssertNil(restored.switchEvent)
    }

    func testTwoLayersRoundTripAndBackgroundAlwaysUsesNormal() throws {
        var config = ActionsConfig()
        config.switchEvent = .find
        config.actions[.auto] = WatchAction(kind: .say, value: "Normal")
        config.alternateActions[.auto] = WatchAction(kind: .say, value: "Must not run")
        config.alternateActions[.rightShort] = WatchAction(kind: .keyboard, keyboard: KeyboardShortcut(repetitions: 2))
        let restored = try JSONDecoder().decode(ActionsConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored, config)
        XCTAssertEqual(restored.action(for: .auto, layer: .alternate), config.actions[.auto])
        XCTAssertEqual(restored.action(for: .unknown, layer: .alternate), .none)
    }

    func testModeSwitchIsIsolatedTrustedAndReversible() {
        var config = ActionsConfig()
        config.switchEvent = .find
        config.alternateActions[.rightShort] = WatchAction(kind: .keyboard, keyboard: KeyboardShortcut(repetitions: 2))
        var modes = ActionModes()
        XCTAssertEqual(modes.resolve(config: config, id: "A", event: .find, authorized: false), .ignored)
        XCTAssertEqual(modes.resolve(config: config, id: "A", event: .find, authorized: true), .switched(.alternate))
        XCTAssertEqual(modes.layer(for: "B"), .normal)
        XCTAssertEqual(modes.resolve(config: config, id: "A", event: .rightShort, authorized: true), .action(config.alternateActions[.rightShort]!))
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
        XCTAssertEqual(plan.count, 10)
        XCTAssertEqual(plan.filter(\.down).map(\.code), plan.filter { !$0.down }.map(\.code).reversed())
        XCTAssertEqual(plan.last?.flags.rawValue, 0)
        XCTAssertEqual(plan[4].code, 124) // Right arrow, from the shared Rust catalog.
        XCTAssertEqual(shortcut.summary, "⌃ ⌥ ⇧ ⌘ + → ×2")
    }

    func testInvalidKeyboardRequestsAreNotPlanned() {
        for repeats in [0, 11, 1000] { XCTAssertNil(KeyboardEmitter.plan(KeyboardShortcut(repetitions: repeats))) }
        XCTAssertNil(KeyboardEmitter.plan(KeyboardShortcut(key: "unknown")))
    }
}
