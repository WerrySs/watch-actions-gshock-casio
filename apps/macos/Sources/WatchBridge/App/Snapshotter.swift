import AppKit
import SwiftUI

/// Design tool: `WatchBridge --snapshot <directory>` renders every screen with sample data.
@MainActor
enum Snapshotter {
    /// Renders isolated controls and reports blank snapshots.
    static func probe(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = WatchStore.preview()
        let probes: [(String, AnyView)] = [
            ("text", AnyView(Text("Hello").font(.title))),
            ("toggle-switch", AnyView(Toggle("A", isOn: .constant(true)).toggleStyle(.switch))),
            ("toggle-adaptive", AnyView(Toggle("A", isOn: .constant(true)).toggleStyle(.accentSwitch))),
            ("datepicker-field", AnyView(DatePicker("", selection: .constant(.now), displayedComponents: .date).datePickerStyle(.field))),
            ("datepicker-stepper", AnyView(DatePicker("", selection: .constant(.now), displayedComponents: .hourAndMinute).datePickerStyle(.stepperField))),
            ("picker-menu", AnyView(Picker("", selection: .constant(0)) { Text("One").tag(0); Text("Two").tag(1) }.pickerStyle(.menu))),
            ("stepper", AnyView(Stepper("Value", value: .constant(3)))),
            ("textfield-rounded", AnyView(TextField("x", text: .constant("Hello")).textFieldStyle(.roundedBorder))),
            ("button-prominent", AnyView(Button("Save") {}.buttonStyle(.borderedProminent))),
            ("button-bordered", AnyView(Button("Test") {}.buttonStyle(.bordered))),
            ("button-adaptive", AnyView(Button("Save") {}.buttonStyle(.accent))),
            ("lcd", AnyView(LCDText(text: "06:20"))),
            ("tile", AnyView(Tile { Text("Tile") })),
            ("fieldlabel", AnyView(FieldLabel(label: "From") { Text("x") })),
            ("darkfield", AnyView(DarkField(placeholder: "p", text: .constant("Hello")))),
            ("scroll-vstack", AnyView(ScrollView { VStack { Text("A"); Text("B") } })),
            ("alarm-row", AnyView(AlarmRow(original: Alarm(number: 1)).environment(store))),
            ("gesture-row", AnyView(GestureRow(event: .find) {}.environment(store))),
        ]
        let big = CGSize(width: 960, height: 760)
        let composites: [(String, AnyView, CGSize)] = [
            ("alarms-view-large", AnyView(AlarmsView().environment(store)), big),
            ("alarms-view-small", AnyView(AlarmsView().environment(store)), CGSize(width: 400, height: 200)),
            ("scroll-alarmrow", AnyView(ScrollView { VStack { AlarmRow(original: Alarm(number: 1)) }.padding(26) }.environment(store)), big),
            ("vstack-title-alarmrow", AnyView(VStack(alignment: .leading) { SectionTitle(eyebrow: "A", title: "B"); AlarmRow(original: Alarm(number: 1)) }.environment(store)), big),
            ("foreach-alarmrows", AnyView(VStack { ForEach(store.alarms) { AlarmRow(original: $0) } }.environment(store)), big),
            ("scroll-foreach", AnyView(ScrollView { VStack { ForEach(store.alarms) { AlarmRow(original: $0) } } }.environment(store)), big),
            ("log-view", AnyView(LogView().environment(store)), big),
            ("settings-view", AnyView(TimerSettingsView().environment(store)), big),
            ("dashboard-view", AnyView(DashboardView().environment(store)), big),
        ]
        for (name, view) in probes {
            let url = directory.appendingPathComponent("probe-\(name).png")
            capture(ZStack { Color(nsColor: .windowBackgroundColor); view.padding(40) }, size: CGSize(width: 400, height: 200), to: url)
            print("\(isBlank(url) ? "BLANK   " : "ok      ") \(name)")
        }
        for (name, view, size) in composites {
            let url = directory.appendingPathComponent("probe-\(name).png")
            capture(ZStack { Color(nsColor: .windowBackgroundColor); view }, size: size, to: url)
            print("\(isBlank(url) ? "BLANK   " : "ok      ") \(name)")
        }
    }

    private static func isBlank(_ url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return true }
        var dark = 0, total = 0
        let step = 4
        var y = 120   // Ignore the title bar and traffic-light controls.
        while y < rep.pixelsHigh {
            var x = 0
            while x < rep.pixelsWide {
                total += 1
                if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5, c.brightnessComponent < 0.6 { dark += 1 }
                x += step
            }
            y += step
        }
        return total == 0 || Double(dark) / Double(total) < 0.05
    }

    static func run(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)
        let fullWindow = CommandLine.arguments.contains("--full-window")
        let minimumSize = CommandLine.arguments.contains("--minimum-size")
        let fullPage = CommandLine.arguments.contains("--full-page")
        if let i = CommandLine.arguments.firstIndex(of: "--only"), CommandLine.arguments.count > i + 1,
           CommandLine.arguments[i + 1] == "keyboard" {
            let editor = KeyboardShortcutEditor(shortcut: KeyboardShortcut(meta: true, repetitions: 2)) { _ in }
            capture(editor, size: CGSize(width: 738, height: 590), to: directory.appendingPathComponent("keyboard.png"))
            print("Keyboard editor preview written to \(directory.path)")
            return
        }
        // Dashboard contains the largest image, so it is captured last to reduce interference.
        let order: [SidebarItem] = [.watches, .reminders, .alarms, .settings, .actions, .log, .watch]
        let connectedStore = WatchStore.preview(connected: true)
        let waitingStore = WatchStore.preview(connected: false)
        if CommandLine.arguments.contains("--action-layers") {
            for store in [connectedStore, waitingStore] {
                store.setModeSwitch(.find)
                store.setAction(WatchAction(kind: .keyboard, keyboard: KeyboardShortcut()), for: .rightShort)
                store.setAction(WatchAction(kind: .keyboard, keyboard: KeyboardShortcut(meta: true, repetitions: 2)), for: .rightShort, layer: .alternate)
                store.setAction(WatchAction(kind: .say, value: "Time for a break"), for: .leftLong, layer: .alternate)
                store.editingLayer = .alternate
            }
        }
        var jobs: [(String, SidebarItem, WatchStore)] = order.map { ("\($0.rawValue).png", $0, connectedStore) } + [("watch-waiting.png", .watch, waitingStore)]
        // `--only <name>` captures one screen; one process per window prevents interference.
        if let i = CommandLine.arguments.firstIndex(of: "--only"), CommandLine.arguments.count > i + 1 {
            let wanted = CommandLine.arguments[i + 1]
            jobs = jobs.filter { $0.0 == "\(wanted).png" }
        }
        for (name, item, store) in jobs {
            let content: AnyView
            if fullWindow {
                content = AnyView(ContentView(initialSelection: item).environment(store))
            } else {
                content = AnyView(SectionContent(item: item).environment(store))
            }
            let url = directory.appendingPathComponent(name)
            // A full-host ScrollView can snapshot transparently, so add a two-point opaque column.
            let wrapped = HStack(spacing: 0) { content; Color.clear.frame(width: 2) }
            let size = fullWindow
                ? CGSize(width: minimumSize ? 1_080 : 1_240, height: fullPage ? 1_680 : (minimumSize ? 700 : 800))
                : CGSize(width: 960, height: 760)
            capture(ZStack { Color(nsColor: .windowBackgroundColor); wrapped }, size: size, to: url)
            print("\(isBlank(url) ? "BLANK   " : "ok      ") \(name)")
        }
        print("Snapshots written to \(directory.path)")
    }

    /// Section content without the native sidebar.
    private struct SectionContent: View {
        let item: SidebarItem
        var body: some View {
            switch item {
            case .watch: DashboardView()
            case .watches: WatchesView()
            case .reminders: RemindersView()
            case .alarms: AlarmsView()
            case .settings: TimerSettingsView()
            case .actions: ActionsView()
            case .log: LogView()
            }
        }
    }

    private static func capture<V: View>(_ view: V, size: CGSize, to url: URL) {
        let hosting = NSHostingView(rootView: view
            .environment(\.snapshotRendering, true)
            .environment(\.controlActiveState, .key)
            .preferredColorScheme(.dark))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = SnapshotWindow(contentRect: hosting.frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.alphaValue = 0.0
        window.orderFront(nil)
        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        hosting.layoutSubtreeIfNeeded()
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: url) }
        window.orderOut(nil)
    }

    /// CI desktops can be smaller than the requested render. Never let AppKit silently
    /// resize the offscreen fixture to the runner's screen and change the tested layout.
    private final class SnapshotWindow: NSWindow {
        // Render an active-looking fixture without activating the app or stealing focus.
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            frameRect
        }
    }
}
