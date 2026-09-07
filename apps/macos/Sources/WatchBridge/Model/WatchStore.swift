import CoreBluetooth
import Foundation
import Observation

/// Application state and orchestration for each watch session.
@MainActor
@Observable
final class WatchStore {
    enum Phase: Equatable { case starting, bluetoothOff, unauthorized, unsupported, waiting, connected }

    var phase: Phase = .starting
    var message = "Starting Bluetooth…"
    var notice: String?

    var watchName: String?
    var battery: Int?
    var temperature: Int?
    var lastSeen: Date?
    var lastTimeSync: Date?
    var homeCity: String?
    var timerSeconds: Int?
    var alarms: [Alarm] = Alarm.defaults
    var alarmsRead = false
    var reminders: [Reminder] = Reminder.defaults
    var remindersRead = false
    var settings: WatchSettings?
    var autoTimeAdjust: Bool?
    var lastEvent: WatchButtonEvent?
    var flashingEvent: WatchButtonEvent?

    private(set) var watches: [SavedWatch] = []
    private(set) var currentWatchID: String?
    private(set) var favoriteWatchID: String?
    private(set) var preferredModel = WatchModelVariant.generic.rawValue
    private(set) var pendingQueue = PendingQueue()
    private(set) var legacyPendingCount = 0
    var pending: [PendingChange] { pendingQueue.pending(for: currentWatchID) }
    var storageWarning: String? { PersistenceStatus.shared.failure }
    private(set) var log: [LogEntry] = []
    private(set) var config = ActionsConfig()
    private(set) var trace: [String] = []

    @ObservationIgnored private let central: WatchCentral
    @ObservationIgnored private let lock = AsyncLock()
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private let persists: Bool
    private(set) var actionRunning = false

    init(bluetooth: Bool = true) {
        central = WatchCentral(enabled: bluetooth)
        persists = bluetooth
        if bluetooth {
            config = Persistence.load(ActionsConfig.self, from: "config.json") ?? ActionsConfig()
            legacyPendingCount = (Persistence.load([PendingChange].self, from: "pending.json") ?? []).count
            pendingQueue = Persistence.load(PendingQueue.self, from: "pending-by-watch-v2.json") ?? PendingQueue()
            log = Persistence.load([LogEntry].self, from: "log.json") ?? []
            watches = (Persistence.load([SavedWatch].self, from: "watches.json") ?? [])
                .sorted { $0.lastSeen > $1.lastSeen }
            currentWatchID = watches.first(where: { $0.connectionCount > 0 })?.id ?? watches.first?.id
            if let favorite = Persistence.load(String.self, from: "favorite-watch.json"),
               watches.contains(where: { $0.id == favorite }) {
                favoriteWatchID = favorite
            }
            if let savedModel = Persistence.load(String.self, from: "preferred-model.json"),
               WatchModelVariant(rawValue: savedModel) != nil {
                preferredModel = savedModel
            }
            restoreLastKnownState()
        }

        central.onManagerState = { [weak self] state in self?.handleManagerState(state) }
        central.onConnected = { [weak self] name, identifier in self?.beginSession(name: name, identifier: identifier) }
        central.onDisconnected = { [weak self] _, _ in self?.handleDisconnected() }
        central.onTrace = { [weak self] line in self?.addTrace(line) }
        handleManagerState(central.managerState)
    }

    // MARK: Derived state

    var isConnected: Bool { phase == .connected && central.isConnected }

    var currentWatch: SavedWatch? {
        guard let currentWatchID else { return watches.first }
        return watches.first { $0.id == currentWatchID }
    }

    /// The Dashboard shows the favorite, or otherwise the connected/most recently seen unit.
    var panelWatch: SavedWatch? {
        if let favoriteWatchID, let favorite = watches.first(where: { $0.id == favoriteWatchID }) {
            return favorite
        }
        return currentWatch ?? watches.first
    }

    var displayedWatchName: String {
        if let panelWatch { return panelWatch.title }
        return SavedWatch.displayName(for: preferredModel)
    }

    var displayedWatchModel: String {
        panelWatch?.effectiveModel ?? preferredModel
    }

    var displayedWatchImageFilename: String? { panelWatch?.imageFilename }

    var displayedBattery: Int? { panelWatch.map(\.lastBattery) ?? battery }
    var displayedTemperature: Int? { panelWatch.map(\.lastTemperature) ?? temperature }
    var displayedLastSeen: Date? {
        guard let panelWatch else { return lastSeen }
        return panelWatch.connectionCount > 0 ? panelWatch.lastSeen : nil
    }
    var displayedLastTimeSync: Date? { panelWatch.map(\.lastTimeSync) ?? lastTimeSync }
    var displayedHomeCity: String? { panelWatch.map(\.lastHomeCity) ?? homeCity }
    var displayedTimerSeconds: Int? { panelWatch.map(\.lastTimerSeconds) ?? timerSeconds }

    var panelStatusTitle: String {
        if isConnected, currentWatchID == panelWatch?.id { return lastEvent?.title ?? "Connected" }
        guard let panelWatch else { return phaseTitle }
        if panelWatch.connectionCount == 0 { return "Saved · not paired" }
        return "Last reading · \(Formatters.dateTime.string(from: panelWatch.lastSeen))"
    }

    var navigationStatus: String {
        if isConnected { return message }
        if let panelWatch, panelWatch.connectionCount > 0 {
            return "Saved data · \(Formatters.dateTime.string(from: panelWatch.lastSeen))"
        }
        if panelWatch != nil { return "Saved watch · waiting to be paired" }
        return message
    }

    var phaseTitle: String {
        switch phase {
        case .starting: "Starting"
        case .bluetoothOff: "Bluetooth is off"
        case .unauthorized: "Bluetooth permission required"
        case .unsupported: "Bluetooth LE unavailable"
        case .waiting: "Waiting for the watch"
        case .connected: "Connected"
        }
    }

    /// Active reminders whose date range includes today, used by the REM indicator.
    var hasReminderToday: Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return reminders.contains { r in
            guard r.enabled, !r.watchTitle.isEmpty else { return false }
            let end = max(r.end, r.start)
            switch r.repeatMode {
            case .never:
                return r.start <= today && today <= end
            case .weekly:
                let wd = cal.component(.weekday, from: today)
                let day = Weekday(rawValue: (wd + 5) % 7) ?? .monday
                return r.days.contains(day) && r.start <= today && today <= end
            case .monthly:
                return cal.component(.day, from: r.start) == cal.component(.day, from: today)
            case .yearly:
                let a = cal.dateComponents([.month, .day], from: r.start)
                let b = cal.dateComponents([.month, .day], from: today)
                return a.month == b.month && a.day == b.day
            }
        }
    }

    // MARK: Bluetooth lifecycle

    private func handleManagerState(_ state: CBManagerState) {
        guard storageWarning == nil else {
            central.stopScanning()
            message = storageWarning ?? "Local data is protected"
            return
        }
        switch state {
        case .poweredOn:
            if phase != .connected { phase = .waiting; message = "Waiting for the watch" }
            central.startScanning()
        case .poweredOff:
            phase = .bluetoothOff; message = "Turn on Bluetooth to communicate with the watch."
        case .unauthorized:
            phase = .unauthorized; message = "Allow WatchBridge in System Settings → Privacy & Security → Bluetooth."
        case .unsupported:
            phase = .unsupported; message = "This Mac does not support Bluetooth LE."
        default:
            phase = .starting; message = "Starting Bluetooth…"
        }
    }

    private func handleDisconnected() {
        if phase == .connected { phase = .waiting; message = "Waiting for the watch" }
    }

    private func addTrace(_ line: String) {
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        let entry = "\(stamp)  \(line)"
        trace.append(entry)
        if trace.count > 400 { trace.removeFirst(trace.count - 400) }
        // Frames may contain watch reminder titles, so the trace remains in memory only.
    }

    private func beginSession(name: String, identifier: UUID) {
        guard storageWarning == nil, RustCore.supports(bluetoothName: name) else {
            central.disconnect()
            return
        }
        guard watches.count < 100 || watches.contains(where: { $0.id == identifier.uuidString }) else {
            showNotice("The watch collection is full. No device was replaced.")
            central.disconnect()
            return
        }
        central.holdSession()
        rememberWatch(identifier: identifier, name: name)
        restoreLastKnownState()
        Task { await runSession(name: name) }
    }

    private func runSession(name: String) async {
        defer { central.disconnect(); central.releaseSession() }
        watchName = name
        lastSeen = .now
        phase = .connected
        message = "Connected"
        var entry = LogEntry()
        entry.watchID = currentWatchID
        entry.watchModel = currentWatch?.effectiveModel
        do {
            try await lock.withLock {
                let features = try await central.request([WatchCode.bleFeatures], expect: WatchCode.bleFeatures)
                let event = WatchProtocol.decodeButton(features)
                guard event != .unknown else { throw BLEError.writeFailed("unsupported connection event; no action or settings sent") }
                entry.event = event
                lastEvent = event
                flash(event)
                message = "Connected · \(event.title)"

                // App handshake expected by the watch while the connection is active.
                _ = try? await central.request([WatchCode.appInfo], expect: WatchCode.appInfo, timeout: 5)

                if currentWatch?.canRunMacActions == true {
                    runAction(config.action(for: event), for: event)
                } else {
                    addTrace("Blocked \(event.display): this physical watch is not trusted to control the Mac")
                }

                if let cond = WatchProtocol.decodeCondition(try await central.request([WatchCode.condition], expect: WatchCode.condition)) {
                    battery = cond.battery; temperature = cond.temperature
                    entry.battery = cond.battery; entry.temperature = cond.temperature
                    updateCurrentWatch()
                }

                // Read and write first; time goes last because the watch may disconnect after receiving it.
                if event == .leftLong { try await refreshAllLocked() }
                if event == .leftLong { entry.applied = try await applyPendingLocked() }

                if config.syncTimeOn.contains(event) || (event == .leftLong && pending.contains(.syncTime)) {
                    entry.timeSynced = try await writeTimeLocked()
                    if let id = currentWatchID { pendingQueue.acknowledge(.syncTime, for: id) }
                    persistPending()
                }
                message = entry.timeSynced ? "Time sent · \(event.title)" : "Connected · \(event.title)"
            }
        } catch {
            if !central.isConnected {
                entry.error = "The watch closed the connection before the session finished"
                message = "The watch closed the connection before the session finished"
            } else {
                entry.error = error.localizedDescription
                message = "Watch error: \(error.localizedDescription)"
            }
        }
        log.insert(entry, at: 0)
        if log.count > 300 { log.removeLast(log.count - 300) }
        Persistence.save(log, as: "log.json")
        updateCurrentWatch()
    }

    private func flash(_ event: WatchButtonEvent) {
        flashingEvent = event
        Task {
            try? await Task.sleep(for: .seconds(3))
            if flashingEvent == event { flashingEvent = nil }
        }
    }

    // MARK: Changes from the interface

    /// Applies a change now when connected, otherwise queues it. Returns true when applied.
    @discardableResult
    func save(_ change: PendingChange) async -> Bool {
        guard change.isValid else { showNotice("The change contains an invalid value."); return false }
        guard storageWarning == nil, let target = currentWatch,
              target.connectionCount > 0, target.manuallyRegistered != true,
              RustCore.supports(model: target.model) else {
            showNotice(storageWarning ?? "Connect a supported physical watch before preparing changes.")
            return false
        }
        let targetID = target.id
        if isConnected {
            do {
                try await lock.withLock {
                    guard currentWatchID == targetID else { throw BLEError.notConnected }
                    try await apply(change)
                }
                updateCurrentWatch()
                showNotice("Saved to the watch.")
                return true
            } catch {
                queue(change, for: targetID)
                showNotice("The watch did not accept the change (\(error.localizedDescription)). It remains queued.")
                return false
            }
        }
        queue(change, for: targetID)
        showNotice("Saved. It will be sent when the watch connects.")
        return false
    }

    func discardPending(_ id: String) {
        if let target = currentWatchID { pendingQueue.changes[target]?.removeAll { $0.id == id } }
        persistPending()
    }

    func setAction(_ action: WatchAction, for event: WatchButtonEvent) {
        var action = action
        action.value = RustCore.sanitize(action.value, limit: 500)
        config.actions[event] = action
        persistConfig()
    }

    func setSyncTime(_ on: Bool, for event: WatchButtonEvent) {
        if on { config.syncTimeOn.insert(event) } else { config.syncTimeOn.remove(event) }
        persistConfig()
    }

    func setTimeOffset(_ seconds: Int) {
        config.timeOffsetSeconds = seconds
        persistConfig()
    }

    func testAction(for event: WatchButtonEvent) {
        flash(event)
        runAction(config.action(for: event), for: event)
    }

    private func runAction(_ action: WatchAction, for event: WatchButtonEvent) {
        guard storageWarning == nil, action.kind != .none, event != .unknown, !actionRunning else { return }
        actionRunning = true
        // Persistent history never includes URLs, phrases, app names, or other configured values.
        addTrace("Action for \(event.display): \(action.kind.label)")
        Task { [weak self] in
            let result = await ActionRunner.run(action)
            self?.actionRunning = false
            self?.addTrace("Action finished: \(result)")
        }
    }

    func clearTrace() {
        trace.removeAll()
        // Also remove a trace file that earlier development builds may have created.
        if persists { Persistence.remove("trace.log") }
    }

    /// Configures the model shown before a physical unit is known.
    func setPreferredModel(_ model: String) {
        guard WatchModelVariant(rawValue: model) != nil else { return }
        preferredModel = model
        if persists { Persistence.save(model, as: "preferred-model.json") }
    }

    /// Associates an exact variant without changing the Bluetooth-detected model.
    func setExactModel(_ model: String, for watchID: String) {
        guard WatchModelVariant(rawValue: model) != nil,
              let index = watches.firstIndex(where: { $0.id == watchID }) else { return }
        watches[index].configuredModel = model
        setPreferredModel(model)
        sortAndPersistWatches()
    }

    /// Changes the Dashboard model before or after registering a unit.
    func setPanelModel(_ model: String) {
        if let panelWatch {
            setExactModel(model, for: panelWatch.id)
        } else {
            setPreferredModel(model)
        }
    }

    func setFavoriteWatch(_ watchID: String?) {
        if let watchID, watches.contains(where: { $0.id == watchID }) {
            favoriteWatchID = watchID
        } else {
            favoriteWatchID = nil
        }
        if persists { Persistence.save(favoriteWatchID ?? "", as: "favorite-watch.json") }
    }

    func toggleFavorite(_ watchID: String) {
        setFavoriteWatch(favoriteWatchID == watchID ? nil : watchID)
    }

    func setAllowsMacActions(_ allowed: Bool, for watchID: String) {
        guard let index = watches.firstIndex(where: { $0.id == watchID }) else { return }
        guard watches[index].connectionCount > 0, watches[index].manuallyRegistered != true,
              RustCore.supports(model: watches[index].model) else {
            showNotice("Pair the physical watch before trusting it to run actions.")
            return
        }
        watches[index].allowsMacActions = allowed
        sortAndPersistWatches()
        showNotice(allowed
            ? "This watch may now start actions on the Mac."
            : "Mac actions are blocked for this watch.")
    }

    /// Imports a sanitized copy off the main thread and discards EXIF, GPS, and the original filename.
    func importWatchImage(from url: URL, for watchID: String) {
        Task {
            do {
                let filename = try await Task.detached(priority: .userInitiated) {
                    try WatchImageStore.importImage(from: url)
                }.value
                guard let index = watches.firstIndex(where: { $0.id == watchID }) else {
                    WatchImageStore.removeImage(named: filename)
                    return
                }
                let previous = watches[index].imageFilename
                watches[index].imageFilename = filename
                sortAndPersistWatches()
                WatchImageStore.removeImage(named: previous)
                showNotice("Local photo saved without metadata.")
            } catch {
                showNotice(error.localizedDescription)
            }
        }
    }

    func removeWatchImage(for watchID: String) {
        guard let index = watches.firstIndex(where: { $0.id == watchID }) else { return }
        let previous = watches[index].imageFilename
        watches[index].imageFilename = nil
        sortAndPersistWatches()
        WatchImageStore.removeImage(named: previous)
        showNotice("The local copy was removed. Your original file was not changed.")
    }

    /// Registers a supported model before Bluetooth has discovered a physical unit.
    @discardableResult
    func registerWatch(model: String, nickname: String = "") -> String? {
        var cleanedModel = model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .uppercased()
        if cleanedModel.hasPrefix("CASIO ") { cleanedModel.removeFirst("CASIO ".count) }
        guard RustCore.supports(model: cleanedModel), watches.count < 100 else {
            showNotice("Choose a supported GW-B5600 model (up to 100 saved watches).")
            return nil
        }
        let now = Date.now
        let id = "MANUAL-\(UUID().uuidString)"
        let exactVariant = WatchModelVariant(rawValue: cleanedModel)
        watches.append(SavedWatch(
            id: id,
            model: cleanedModel,
            displayName: SavedWatch.displayName(for: cleanedModel),
            firstSeen: now,
            lastSeen: now,
            connectionCount: 0,
            configuredModel: exactVariant?.rawValue,
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            manuallyRegistered: true,
            allowsMacActions: false
        ))
        if currentWatchID == nil { currentWatchID = id }
        if favoriteWatchID == nil { favoriteWatchID = id }
        setPreferredModel(exactVariant?.rawValue ?? preferredModel)
        sortAndPersistWatches()
        if persists { Persistence.save(favoriteWatchID ?? "", as: "favorite-watch.json") }
        showNotice("Watch added to your collection.")
        return id
    }

    private func queue(_ change: PendingChange, for id: String) {
        pendingQueue.enqueue(change, for: id)
        persistPending()
    }

    private func persistPending() { if persists { Persistence.save(pendingQueue, as: "pending-by-watch-v2.json") } }
    private func persistConfig() { if persists { Persistence.save(config, as: "config.json") } }

    private func rememberWatch(identifier: UUID, name: String) {
        let id = identifier.uuidString
        let now = Date.now
        let model = SavedWatch.modelName(from: name)
        currentWatchID = id
        if let index = watches.firstIndex(where: { $0.id == id }) {
            watches[index].model = model
            watches[index].displayName = SavedWatch.displayName(for: model)
            watches[index].lastSeen = now
            watches[index].connectionCount = min(watches[index].connectionCount, Int.max - 1) + 1
            watches[index].manuallyRegistered = false
        } else {
            watches.append(SavedWatch(
                id: id,
                model: model,
                displayName: SavedWatch.displayName(for: model),
                firstSeen: now,
                lastSeen: now,
                connectionCount: 1,
                configuredModel: preferredModel,
                allowsMacActions: false
            ))
        }
        sortAndPersistWatches()
    }

    private func updateCurrentWatch() {
        guard let currentWatchID, let index = watches.firstIndex(where: { $0.id == currentWatchID }) else { return }
        if let watchName {
            let model = SavedWatch.modelName(from: watchName)
            watches[index].model = model
            watches[index].displayName = SavedWatch.displayName(for: model)
        }
        if let battery { watches[index].lastBattery = battery }
        if let temperature { watches[index].lastTemperature = temperature }
        if let lastTimeSync { watches[index].lastTimeSync = lastTimeSync }
        if let homeCity { watches[index].lastHomeCity = homeCity }
        if let timerSeconds { watches[index].lastTimerSeconds = timerSeconds }
        if alarmsRead { watches[index].lastAlarms = alarms }
        if remindersRead { watches[index].lastReminders = reminders }
        if let settings { watches[index].lastSettings = settings }
        if let autoTimeAdjust { watches[index].lastAutoTimeAdjust = autoTimeAdjust }
        if let lastEvent { watches[index].lastEvent = lastEvent }
        sortAndPersistWatches()
    }

    func linkRegistration(_ manualID: String, to physicalID: String) {
        guard storageWarning == nil,
              let manual = watches.first(where: { $0.id == manualID && $0.manuallyRegistered == true && $0.connectionCount == 0 }),
              let index = watches.firstIndex(where: { $0.id == physicalID && $0.connectionCount > 0 && $0.manuallyRegistered != true }),
              RustCore.supports(model: watches[index].model), RustCore.supports(model: manual.effectiveModel) else { return }
        watches[index].configuredModel = manual.effectiveModel
        watches[index].nickname = manual.nickname
        if let image = manual.imageFilename { watches[index].imageFilename = image }
        watches[index].allowsMacActions = false
        watches.removeAll { $0.id == manualID }
        if favoriteWatchID == manualID { setFavoriteWatch(physicalID) }
        if currentWatchID == manualID { currentWatchID = physicalID; restoreLastKnownState() }
        sortAndPersistWatches()
        showNotice("Registration linked to this physical watch. Actions remain blocked until you allow them.")
    }

    private func restoreLastKnownState() {
        guard let watch = currentWatch else { return }
        alarms = Alarm.defaults; alarmsRead = false
        reminders = Reminder.defaults; remindersRead = false
        battery = watch.lastBattery
        temperature = watch.lastTemperature
        lastSeen = watch.connectionCount > 0 ? watch.lastSeen : nil
        lastTimeSync = watch.lastTimeSync
        homeCity = watch.lastHomeCity
        timerSeconds = watch.lastTimerSeconds
        if let saved = watch.lastAlarms, saved.count == 5,
           saved.enumerated().allSatisfy({ $0.element.number == $0.offset + 1 && PendingChange.alarm($0.element).isValid }) {
            alarms = saved; alarmsRead = true
        }
        if let saved = watch.lastReminders, saved.count == Reminder.slots,
           saved.enumerated().allSatisfy({ $0.element.slot == $0.offset + 1 && PendingChange.reminder($0.element).isValid }) {
            reminders = saved; remindersRead = true
        }
        settings = watch.lastSettings
        autoTimeAdjust = watch.lastAutoTimeAdjust
        lastEvent = watch.lastEvent
    }

    private func sortAndPersistWatches() {
        watches.sort { $0.lastSeen > $1.lastSeen }
        if persists { Persistence.save(watches, as: "watches.json") }
    }

    /// Sample data for previews and design snapshots. Bluetooth is disabled.
    static func preview(connected: Bool = true) -> WatchStore {
        let s = WatchStore(bluetooth: false)
        let cal = Calendar.current
        s.phase = connected ? .connected : .waiting
        s.message = connected ? "Connected · Button C, hold for 3 seconds" : "Waiting for the watch"
        s.watchName = "CASIO GW-B5600"
        s.battery = 100
        s.temperature = 31
        s.lastSeen = .now.addingTimeInterval(-90)
        s.lastTimeSync = .now.addingTimeInterval(-3600 * 5)
        s.homeCity = "MADRID"
        s.timerSeconds = 601
        s.alarms = Alarm.defaults
        s.alarms[0] = Alarm(number: 1, hour: 6, minute: 20, enabled: true, hourlyChime: false)
        s.alarms[2] = Alarm(number: 3, hour: 14, minute: 45, enabled: false, hourlyChime: false)
        s.alarmsRead = true
        var r = Reminder.defaults
        r[0].title = "Saga Game Fest"; r[0].enabled = true
        r[0].start = cal.date(from: DateComponents(year: 2026, month: 10, day: 9))!; r[0].end = r[0].start
        r[1].title = "Gym"; r[1].enabled = true; r[1].repeatMode = .weekly; r[1].days = [.monday, .wednesday, .friday]
        r[1].start = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        r[1].end = cal.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        r[2].title = "Dentist 17:30"; r[2].enabled = false
        s.reminders = r
        s.remindersRead = true
        s.settings = WatchSettings()
        s.autoTimeAdjust = true
        s.lastEvent = connected ? .leftLong : nil
        let previewID = "PREVIEW-GW-B5600"
        s.watches = [SavedWatch(
            id: previewID,
            model: "GW-B5600",
            displayName: "CASIO GW-B5600",
            firstSeen: .now.addingTimeInterval(-3600 * 24 * 180),
            lastSeen: s.lastSeen ?? .now,
            connectionCount: 84,
            lastBattery: s.battery,
            lastTemperature: s.temperature,
            configuredModel: WatchModelVariant.redComposite.rawValue,
            nickname: "Daily watch",
            allowsMacActions: true,
            lastTimeSync: s.lastTimeSync,
            lastHomeCity: s.homeCity,
            lastTimerSeconds: s.timerSeconds,
            lastAlarms: s.alarms,
            lastReminders: s.reminders,
            lastSettings: s.settings,
            lastAutoTimeAdjust: s.autoTimeAdjust,
            lastEvent: s.lastEvent
        ), SavedWatch(
            id: "PREVIEW-MANUAL-GWB5600",
            model: "GW-B5600-2",
            displayName: "CASIO GW-B5600-2",
            firstSeen: .now.addingTimeInterval(-3600 * 24 * 4),
            lastSeen: .now.addingTimeInterval(-3600 * 24 * 4),
            connectionCount: 0,
            nickname: "Blue square",
            manuallyRegistered: true
        )]
        s.currentWatchID = previewID
        s.favoriteWatchID = previewID
        s.preferredModel = WatchModelVariant.redComposite.rawValue
        s.config = ActionsConfig()
        s.config.actions[.leftLong] = WatchAction(kind: .say, value: "Time for a break")
        s.config.actions[.rightShort] = WatchAction(kind: .openApp, value: "Music")
        if !connected { s.pendingQueue.changes[previewID] = [.reminder(r[2]), .syncTime] }
        s.log = [
            LogEntry(date: .now.addingTimeInterval(-90), event: .leftLong, battery: 100, temperature: 31, timeSynced: true, applied: ["Reminder 2: Gym"], watchID: previewID, watchModel: WatchModelVariant.redComposite.rawValue),
            LogEntry(date: .now.addingTimeInterval(-3600 * 5), event: .rightShort, battery: 100, temperature: 30, timeSynced: true, watchID: previewID, watchModel: WatchModelVariant.redComposite.rawValue),
            LogEntry(date: .now.addingTimeInterval(-3600 * 11), event: .auto, battery: 100, temperature: 24, timeSynced: true, watchID: previewID, watchModel: WatchModelVariant.redComposite.rawValue),
            LogEntry(date: .now.addingTimeInterval(-3600 * 26), event: .find, battery: 100, temperature: 29, watchID: previewID, watchModel: WatchModelVariant.redComposite.rawValue),
        ]
        s.trace = ["21:17:53  Saw CASIO GW-B5600 (-63 dBm)", "21:17:54  Connected to CASIO GW-B5600", "21:17:54  → 10",
                   "21:17:54  ← 10 41 9E 15 C1 A1 EE 7F 01 03 0F FF FF FF FF 18 00 00 00", "21:17:55  → 28", "21:17:55  ← 28 13 20 00",
                   "21:17:57  → 1F 00", "21:17:57  ← 1F 00 4D 41 44 52 49 44 00 00 00 00 00 00 00 00 00 00 00 00",
                   "21:17:58  ⇒ 09 EA 07 09 03 15 11 3A 03 BF 01", "21:18:00  → 30 01",
                   "21:18:00  ← 30 01 53 61 67 61 20 47 61 6D 65 20 46 65 73 74 00 00 00 00"]
        return s
    }

    private func showNotice(_ text: String) {
        notice = storageWarning ?? text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { notice = nil }
        }
    }

    // MARK: Watch operations (always inside the asynchronous lock)

    private func apply(_ change: PendingChange) async throws {
        guard storageWarning == nil, change.isValid else { throw BLEError.writeFailed("invalid change or protected local state") }
        switch change {
        case .reminder(let r): try await writeReminderLocked(r)
        case .alarm(let a): try await writeAlarmLocked(a)
        case .timer(let s): try await writeTimerLocked(s)
        case .settings(let s): try await writeSettingsLocked(s)
        case .autoTimeAdjust(let on): try await writeAutoTimeAdjustLocked(on)
        case .syncTime: _ = try await writeTimeLocked()
        }
    }

    private func applyPendingLocked() async throws -> [String] {
        guard !pending.isEmpty else { return [] }
        message = "Sending pending changes…"
        var applied: [String] = []
        for item in pending where item != .syncTime {
            try await apply(item)
            applied.append(item.summary)
            if let id = currentWatchID { pendingQueue.acknowledge(item, for: id) }
            persistPending()
        }
        return applied
    }

    private func writeReminderLocked(_ r: Reminder) async throws {
        try await central.write(WatchProtocol.encodeReminderTitle(r))
        try await central.write(WatchProtocol.encodeReminderTime(r))
        reminders[r.slot - 1] = r
    }

    private func readAlarmsLocked() async throws -> [Alarm] {
        let first = try await central.request([WatchCode.alarm1], expect: WatchCode.alarm1)
        let rest = try await central.request([WatchCode.alarms2to5], expect: WatchCode.alarms2to5)
        guard let list = WatchProtocol.decodeAlarms(first: first, rest: rest) else {
            throw BLEError.writeFailed("unrecognized alarm response")
        }
        alarms = list
        alarmsRead = true
        return list
    }

    private func writeAlarmLocked(_ a: Alarm) async throws {
        var list = alarmsRead ? alarms : try await readAlarmsLocked()
        list[a.number - 1] = a
        let packets = WatchProtocol.encodeAlarms(list)
        try await central.write(packets.first)
        try await central.write(packets.rest)
        alarms = list
    }

    private func writeTimerLocked(_ seconds: Int) async throws {
        try await central.write(WatchProtocol.encodeTimer(seconds))
        timerSeconds = seconds
    }

    private func writeSettingsLocked(_ s: WatchSettings) async throws {
        try await central.write(WatchProtocol.encodeSettings(s))
        settings = s
    }

    private func writeAutoTimeAdjustLocked(_ on: Bool) async throws {
        let raw = try await central.request([WatchCode.timeAdjustment], expect: WatchCode.timeAdjustment)
        try await central.write(WatchProtocol.encodeAutoTimeAdjust(original: raw, enabled: on))
        autoTimeAdjust = on
    }

    /// Replays daylight-saving and city state before sending the current time.
    private func writeTimeLocked() async throws -> Bool {
        guard storageWarning == nil else { throw BLEError.writeFailed("local state is protected") }
        message = "Setting the watch time…"
        // Read and replay daylight-saving and city state. Missing optional responses do not
        // stop the operation because the time must be sent before the watch disconnects.
        for state: UInt8 in [0, 2, 4] {
            await echo([WatchCode.dstWatchState, state])
        }
        for city: UInt8 in 0..<6 {
            await echo([WatchCode.dstSetting, city])
        }
        for city: UInt8 in 0..<6 {
            if let r = await echo([WatchCode.worldCities, city]), city == 0 { homeCity = WatchProtocol.decodeCity(r) }
        }
        guard central.isConnected else { throw BLEError.notConnected }
        let target = Date().addingTimeInterval(TimeInterval(config.timeOffsetSeconds))
        try await central.write(WatchProtocol.encodeTime(target))
        lastTimeSync = .now
        return true
    }

    /// Requests a frame and writes it back unchanged. Returns nil when the watch times out.
    @discardableResult
    private func echo(_ request: [UInt8]) async -> [UInt8]? {
        do {
            let r = try await central.request(request, expect: request[0], timeout: 4)
            try await central.write(r, timeout: 4)
            return r
        } catch {
            addTrace("No response to \(WatchProtocol.hex(request)); continuing (\(error.localizedDescription))")
            return nil
        }
    }

    private func refreshAllLocked() async throws {
        message = "Reading the watch…"
        if let raw = try? await central.request([WatchCode.watchName], expect: WatchCode.watchName, timeout: 6) {
            let n = WatchProtocol.decodeName(raw)
            if !n.isEmpty {
                guard RustCore.supports(model: SavedWatch.modelName(from: n)) else {
                    throw BLEError.writeFailed("the watch reports an unsupported model; no settings sent")
                }
                watchName = n; updateCurrentWatch()
            }
        }
        homeCity = WatchProtocol.decodeCity(try await central.request([WatchCode.worldCities, 0], expect: WatchCode.worldCities))
        timerSeconds = WatchProtocol.decodeTimer(try await central.request([WatchCode.timer], expect: WatchCode.timer))
        _ = try await readAlarmsLocked()
        settings = WatchProtocol.decodeSettings(try await central.request([WatchCode.basicSettings], expect: WatchCode.basicSettings))
        autoTimeAdjust = WatchProtocol.decodeAutoTimeAdjust(try await central.request([WatchCode.timeAdjustment], expect: WatchCode.timeAdjustment))
        var list = Reminder.defaults
        for slot in 1...Reminder.slots {
            let title = try await central.request([WatchCode.reminderTitle, UInt8(slot)], expect: WatchCode.reminderTitle)
            let time = try await central.request([WatchCode.reminderTime, UInt8(slot)], expect: WatchCode.reminderTime)
            var r = Reminder(slot: slot)
            guard let decodedTitle = WatchProtocol.decodeReminderTitle(title), WatchProtocol.decodeReminderTime(time, into: &r) else {
                throw BLEError.writeFailed("unrecognized reminder response")
            }
            r.title = decodedTitle
            list[slot - 1] = r
        }
        reminders = list
        remindersRead = true
    }
}
