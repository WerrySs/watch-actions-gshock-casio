import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case watch, watches, reminders, alarms, settings, actions, log
    var id: String { rawValue }
    var title: String {
        switch self {
        case .watch: "Dashboard"
        case .watches: "My Watches"
        case .reminders: "Reminders"
        case .alarms: "Alarms"
        case .settings: "Watch Settings"
        case .actions: "Actions"
        case .log: "Connection History"
        }
    }
    var icon: String {
        switch self {
        case .watch: "applewatch"
        case .watches: "square.stack.3d.up"
        case .reminders: "text.badge.checkmark"
        case .alarms: "alarm"
        case .settings: "slider.horizontal.3"
        case .actions: "bolt"
        case .log: "list.bullet.rectangle"
        }
    }
    static let watchSection: [SidebarItem] = [.watch, .watches, .reminders, .alarms, .settings]
    static let macSection: [SidebarItem] = [.actions, .log]
}

@MainActor
struct ContentView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.snapshotRendering) private var snapshotRendering
    @State private var selection: SidebarItem?

    init(initialSelection: SidebarItem = .watch) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Watch") {
                    ForEach(SidebarItem.watchSection) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
                Section("Computer") {
                    ForEach(SidebarItem.macSection) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(snapshotRendering ? .hidden : .automatic)
            .background(snapshotRendering ? Color(nsColor: .underPageBackgroundColor) : Color.clear)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            ZStack {
                if snapshotRendering {
                    Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                } else {
                    VisualEffect().ignoresSafeArea()
                }
                content.id(store.currentWatchID)
                    .disabled(store.storageWarning != nil)
            }
        }
        .navigationTitle(selection?.title ?? "WatchBridge")
        .navigationSubtitle(store.navigationStatus)
        .safeAreaInset(edge: .top) {
            if let warning = store.storageWarning {
                Label(warning, systemImage: "exclamationmark.shield")
                    .font(.callout).padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
            } else if store.legacyPendingCount > 0 {
                Text("Old unassigned changes were preserved but will not be sent. Recreate them for the intended physical watch.")
                    .font(.callout).padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
            } else if [.reminders, .alarms, .settings].contains(selection ?? .watch), let watch = store.currentWatch {
                Label("Changes target: \(watch.title)", systemImage: "applewatch")
                    .font(.callout).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.testAction(for: .find)
                } label: { Label("Find this Mac", systemImage: "bell.and.waves.left.and.right") }
                    .help("Run the FIND action without touching the watch")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.save(.syncTime) }
                } label: { Label("Set watch time", systemImage: "clock.arrow.2.circlepath") }
                    .help("Send the Mac time now or queue it until the watch connects")
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = store.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: store.notice)
    }

    @ViewBuilder private var content: some View {
        switch selection ?? .watch {
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
