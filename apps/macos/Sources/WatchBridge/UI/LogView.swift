import SwiftUI

@MainActor
struct LogView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(eyebrow: "History", title: "Connection history", detail: "\(store.log.count) saved on this Mac")
            VSplitView {
                Tile(padding: 0) {
                    if store.log.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "applewatch.radiowaves.left.and.right").font(.system(size: 28)).foregroundStyle(Theme.text3)
                            Text("No connections yet").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text2)
                            Text("Each connection records the gesture, battery, and changes that were sent.").font(.system(size: 12)).foregroundStyle(Theme.text3)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Table(store.log) {
                            TableColumn("When") { Text(Formatters.dateTime.string(from: $0.date)) }.width(110)
                            TableColumn("Watch") { entry in
                                Text(entry.watchModel.map { SavedWatch.displayName(for: $0) } ?? "—")
                                    .lineLimit(1)
                            }.width(min: 120, ideal: 145)
                            TableColumn("Gesture") { entry in
                                HStack(spacing: 8) { GestureBadge(event: entry.event); Text(entry.event.title) }
                            }.width(min: 200)
                            TableColumn("Battery") { Text($0.battery.map { "\($0) %" } ?? "") }.width(60)
                            TableColumn("Temp.") { Text($0.temperature.map { "\($0) °C" } ?? "") }.width(50)
                            TableColumn("Time") { entry in
                                if entry.timeSynced { Image(systemName: "checkmark").foregroundStyle(Theme.good) } else { Text("") }
                            }.width(40)
                            TableColumn("Sent") { Text($0.applied.joined(separator: ", ")) }
                            TableColumn("Issue") { Text($0.error ?? "").foregroundStyle(Theme.bad) }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(minHeight: 180)

                Tile(padding: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Label("Bluetooth trace", systemImage: "waveform.path").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("this session only; never written to disk").font(.system(size: 11)).foregroundStyle(Theme.text3)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(store.trace.joined(separator: "\n"), forType: .string)
                            }.buttonStyle(.ghost)
                            Button("Clear") { store.clearTrace() }.buttonStyle(.ghost)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        Rectangle().fill(Theme.stroke).frame(height: 1)
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 1) {
                                    ForEach(Array(store.trace.enumerated()), id: \.offset) { i, line in
                                        Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).id(i)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                            }
                            .onChange(of: store.trace.count) { if let last = store.trace.indices.last { proxy.scrollTo(last) } }
                        }
                    }
                }
                .frame(minHeight: 120, idealHeight: 200)
                .padding(.top, 10)
            }
        }
        .padding(26)
    }
}
