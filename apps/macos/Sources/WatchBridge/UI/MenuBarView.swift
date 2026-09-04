import SwiftUI

@MainActor
struct MenuBarView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(store.phase == .connected ? Color.green : store.phase == .waiting ? Color.orange : Color.red)
                    .frame(width: 9, height: 9)
                Text(store.phaseTitle).font(.headline)
                Spacer()
                if let battery = store.battery { Label("\(battery) %", systemImage: "battery.75percent").font(.caption) }
            }
            Text(store.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let last = store.lastSeen {
                Text("Last connection: \(Formatters.dateTime.string(from: last))").font(.caption2).foregroundStyle(.tertiary)
            }
            if !store.pending.isEmpty {
                Text("\(store.pending.count) pending changes").font(.caption).foregroundStyle(.orange)
            }
            Divider()
            Button {
                Task { await store.save(.syncTime) }
            } label: { Label("Set watch time", systemImage: "clock.arrow.2.circlepath") }
            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            } label: { Label("Open WatchBridge", systemImage: "macwindow") }
            Divider()
            Button("Quit WatchBridge") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 300)
    }
}
