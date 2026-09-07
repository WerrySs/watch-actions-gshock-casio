@preconcurrency import CoreBluetooth
import Foundation

enum WatchBluetoothUUID {
    static var service: CBUUID { CBUUID(string: "26EB000D-B012-49A8-B1F8-394FB2032B0F") }
    static var request: CBUUID { CBUUID(string: "26EB002C-B012-49A8-B1F8-394FB2032B0F") }
    static var allFeatures: CBUUID { CBUUID(string: "26EB002D-B012-49A8-B1F8-394FB2032B0F") }
}

enum BLEError: LocalizedError {
    case notConnected
    case timeout(UInt8)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "the watch is not connected"
        case .timeout(let code): String(format: "the watch did not respond to command %02X", code)
        case .writeFailed(let why): "could not write to the watch: \(why)"
        }
    }
}

/// CoreBluetooth adapter that discovers a watch, connects when it advertises, and exposes async requests.
/// Everything runs on the main queue and the class is isolated to `MainActor`.
@MainActor
final class WatchCentral: NSObject {
    var onManagerState: (@MainActor (CBManagerState) -> Void)?
    var onConnected: (@MainActor (String, UUID) -> Void)?
    var onDisconnected: (@MainActor (String?, Error?) -> Void)?
    var onTrace: (@MainActor (String) -> Void)?

    private(set) var isConnected = false
    private(set) var watchName: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var requestChar: CBCharacteristic?
    private var featuresChar: CBCharacteristic?
    private var pendingNotifyEnables = 0
    private var wantScanning = false
    private var sessionHeld = false
    private let writeLock = AsyncLock()
    private var answeringChallenge = false
    private var setupTimeout: Task<Void, Never>?

    func holdSession() { sessionHeld = true }
    func releaseSession() {
        sessionHeld = false
        if wantScanning { startScanning() }
    }

    private struct Waiter { let id = UUID(); let continuation: CheckedContinuation<[UInt8], Error> }
    private var waiters: [UInt8: Waiter] = [:]
    private struct WriteWaiter { let id = UUID(); let continuation: CheckedContinuation<Void, Error> }
    private var writeWaiter: WriteWaiter?

    init(enabled: Bool = true) {
        super.init()
        if enabled { central = CBCentralManager(delegate: self, queue: .main) }
    }

    var managerState: CBManagerState { central?.state ?? .unknown }

    // MARK: Discovery and connection

    func startScanning() {
        wantScanning = true
        guard !sessionHeld, let central, central.state == .poweredOn, peripheral == nil, !central.isScanning else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        onTrace?("Scanning for the watch…")
    }

    func stopScanning() {
        wantScanning = false
        central?.stopScan()
    }

    func disconnect() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
    }

    // MARK: Request and response

    /// Writes a request without response and waits for a frame beginning with `code`.
    func request(_ bytes: [UInt8], expect code: UInt8, timeout: TimeInterval = 15) async throws -> [UInt8] {
        guard isConnected, let p = peripheral, let rc = requestChar else { throw BLEError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            if let old = waiters.removeValue(forKey: code) { old.continuation.resume(throwing: BLEError.timeout(code)) }
            let waiter = Waiter(continuation: continuation)
            waiters[code] = waiter
            onTrace?("→ \(WatchProtocol.hex(bytes))")
            p.writeValue(Data(bytes), for: rc, type: .withoutResponse)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self, let current = self.waiters[code], current.id == waiter.id else { return }
                self.waiters.removeValue(forKey: code)
                current.continuation.resume(throwing: BLEError.timeout(code))
            }
        }
    }

    /// Writes data with response to the primary characteristic.
    func write(_ bytes: [UInt8], timeout: TimeInterval = 10) async throws {
        try await writeLock.withLock {
            try await writeLocked(bytes, timeout: timeout)
        }
    }

    private func writeLocked(_ bytes: [UInt8], timeout: TimeInterval) async throws {
        guard isConnected, let p = peripheral, let fc = featuresChar else { throw BLEError.notConnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if let old = writeWaiter { writeWaiter = nil; old.continuation.resume(throwing: BLEError.writeFailed("replaced by another write")) }
            let waiter = WriteWaiter(continuation: continuation)
            writeWaiter = waiter
            onTrace?("⇒ \(WatchProtocol.hex(bytes))")
            p.writeValue(Data(bytes), for: fc, type: .withResponse)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self, let current = self.writeWaiter, current.id == waiter.id else { return }
                self.writeWaiter = nil
                // A late acknowledgement must never confirm a later write.
                self.isConnected = false
                self.disconnect()
                current.continuation.resume(throwing: BLEError.timeout(bytes.first ?? 0))
            }
        }
    }

    // MARK: Main-thread event handling

    private func handleStateUpdate() {
        guard let central else { return }
        onManagerState?(central.state)
        if central.state == .poweredOn, wantScanning { startScanning() }
        if central.state != .poweredOn, peripheral != nil { cleanup(error: nil) }
    }

    private func handleDiscover(_ peripheral: CBPeripheral, name: String, rssi: NSNumber) {
        guard wantScanning, !sessionHeld, RustCore.supports(bluetoothName: name), self.peripheral == nil else { return }
        onTrace?("Saw \(name) (\(rssi) dBm)")
        watchName = name
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
        setupTimeout?.cancel()
        setupTimeout = Task { [weak self, weak peripheral] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, let peripheral,
                  self.peripheral === peripheral, !self.isConnected else { return }
            self.onTrace?("Bluetooth connection setup timed out")
            self.central?.cancelPeripheralConnection(peripheral)
            self.cleanup(error: BLEError.timeout(WatchCode.bleFeatures))
        }
    }

    private func handleCharacteristics(_ characteristics: [CBCharacteristic], of peripheral: CBPeripheral) {
        for c in characteristics {
            if c.uuid == WatchBluetoothUUID.request { requestChar = c }
            if c.uuid == WatchBluetoothUUID.allFeatures { featuresChar = c }
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                pendingNotifyEnables += 1
                peripheral.setNotifyValue(true, for: c)
            }
        }
        finishSetupIfReady()
    }

    private func handleNotifyState() {
        pendingNotifyEnables = max(0, pendingNotifyEnables - 1)
        finishSetupIfReady()
    }

    private func handleWriteResult(_ error: Error?) {
        guard let w = writeWaiter else { return }
        writeWaiter = nil
        if let error { w.continuation.resume(throwing: BLEError.writeFailed(error.localizedDescription)) }
        else { w.continuation.resume() }
    }

    private func handleValue(_ bytes: [UInt8], from peripheral: CBPeripheral) {
        onTrace?("← \(WatchProtocol.hex(bytes))")
        if WatchProtocol.isAppInfoChallenge(bytes), !answeringChallenge {
            // The watch checks the client and may disconnect without this response.
            // Use the same serialized write path: this ACK cannot acknowledge a settings write.
            answeringChallenge = true
            Task { [weak self] in
                guard let self else { return }
                defer { self.answeringChallenge = false }
                do { try await self.write(WatchProtocol.appInfoResponse, timeout: 5) }
                catch { self.onTrace?("Watch handshake failed: \(error.localizedDescription)") }
            }
        }
        if let w = waiters.removeValue(forKey: bytes[0]) {
            w.continuation.resume(returning: bytes)
        }
    }

    private func failAll(_ error: Error) {
        for (_, w) in waiters { w.continuation.resume(throwing: error) }
        waiters.removeAll()
        if let w = writeWaiter { writeWaiter = nil; w.continuation.resume(throwing: error) }
    }

    private func cleanup(error: Error?) {
        setupTimeout?.cancel()
        setupTimeout = nil
        let name = watchName
        isConnected = false
        failAll(error ?? BLEError.notConnected)
        peripheral?.delegate = nil
        peripheral = nil
        requestChar = nil
        featuresChar = nil
        pendingNotifyEnables = 0
        onDisconnected?(name, error)
        if wantScanning {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.startScanning()
            }
        }
    }

    private func finishSetupIfReady() {
        guard !isConnected, pendingNotifyEnables == 0, requestChar != nil, featuresChar != nil else { return }
        isConnected = true
        setupTimeout?.cancel()
        setupTimeout = nil
        onTrace?("Connected to \(watchName ?? "watch")")
        onConnected?(watchName ?? "CASIO", peripheral?.identifier ?? UUID())
    }
}

// MARK: - CoreBluetooth delegates
// Callbacks arrive on the main queue configured above, so `assumeIsolated` is safe here.

extension WatchCentral: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { handleStateUpdate() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        MainActor.assumeIsolated { handleDiscover(peripheral, name: name, rssi: RSSI) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([WatchBluetoothUUID.service])
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            guard self.peripheral === peripheral else { return }
            onTrace?("Connection failed: \(error?.localizedDescription ?? "unknown")")
            cleanup(error: error)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            guard self.peripheral === peripheral else { return }
            onTrace?("Disconnected")
            cleanup(error: error)
        }
    }
}

extension WatchCentral: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services?.filter({ $0.uuid == WatchBluetoothUUID.service }), !services.isEmpty else {
            MainActor.assumeIsolated {
                onTrace?("The watch does not expose the expected compatibility service")
                central?.cancelPeripheralConnection(peripheral)
            }
            return
        }
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, service.uuid == WatchBluetoothUUID.service else { return }
        let characteristics = service.characteristics ?? []
        MainActor.assumeIsolated { handleCharacteristics(characteristics, of: peripheral) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard self.peripheral === peripheral else { return }
            if let error { central?.cancelPeripheralConnection(peripheral); cleanup(error: error) }
            else { handleNotifyState() }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard self.peripheral === peripheral, characteristic.uuid == WatchBluetoothUUID.allFeatures else { return }
            handleWriteResult(error)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == WatchBluetoothUUID.request || characteristic.uuid == WatchBluetoothUUID.allFeatures,
              let data = characteristic.value, !data.isEmpty else { return }
        let bytes = [UInt8](data)
        MainActor.assumeIsolated {
            guard self.peripheral === peripheral else { return }
            handleValue(bytes, from: peripheral)
        }
    }
}
