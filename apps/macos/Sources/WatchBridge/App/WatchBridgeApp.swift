import SwiftUI

@main
@MainActor
struct WatchBridgeApp: App {
    @State private var store = WatchStore(bluetooth: !CommandLine.arguments.contains("--snapshot") && !CommandLine.arguments.contains("--probe") && !CommandLine.arguments.contains("--smoke-test"))

    init() {
        if CommandLine.arguments.contains("--smoke-test") {
            guard RustCore.supports(model: "GW-B5600"), RustCore.decodeButton([]) == .unknown else { exit(1) }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
            Snapshotter.run(into: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--probe"), CommandLine.arguments.count > i + 1 {
            Snapshotter.probe(into: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("WatchBridge") {
            ContentView()
                .environment(store)
                .frame(minWidth: 1_080, idealWidth: 1_240, minHeight: 700, idealHeight: 800)
        }
        .defaultSize(width: 1_240, height: 800)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView().environment(store)
        } label: {
            Image(systemName: store.phase == .connected ? "applewatch.radiowaves.left.and.right" : "applewatch")
        }
        .menuBarExtraStyle(.window)
    }
}
