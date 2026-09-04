import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DashboardView: View {
    @Environment(WatchStore.self) private var store
    @State private var editingEvent: WatchButtonEvent?
    @State private var choosingPhoto = false

    var body: some View {
        HStack(spacing: 0) {
            hero.frame(width: 420)
            Rectangle().fill(Theme.stroke).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    statsGrid
                    gestures
                    if !store.pending.isEmpty { pending }
                }
                .padding(26)
            }
        }
        .sheet(item: $editingEvent) { event in ActionSheet(event: event) }
        .fileImporter(
            isPresented: $choosingPhoto,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result,
               let url = urls.first,
               let watchID = store.panelWatch?.id {
                store.importWatchImage(from: url, for: watchID)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            WatchModelImage(
                model: store.displayedWatchModel,
                imageFilename: store.displayedWatchImageFilename
            )
                .frame(width: 350, height: 430)
                .background {
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [Theme.accent.opacity(store.phase == .connected ? 0.22 : 0.08), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 150
                        ))
                        .frame(width: 320, height: 410)
                        .blur(radius: 32)
                        .offset(y: 10)
                }
            VStack(spacing: 8) {
                Text(store.displayedWatchName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                StatusChip(
                    color: store.isConnected && store.currentWatchID == store.panelWatch?.id ? Theme.good : Theme.warn,
                    text: store.panelStatusTitle
                )
                if WatchModelVariant.matching(store.displayedWatchModel) != nil {
                    HStack(spacing: 8) {
                        Text("Exact model")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.text2)
                        ModelPicker(selection: Binding(
                            get: {
                                WatchModelVariant(rawValue: store.displayedWatchModel)?.rawValue
                                    ?? WatchModelVariant.matching(store.displayedWatchModel)?.rawValue
                                    ?? WatchModelVariant.generic.rawValue
                            },
                            set: { store.setPanelModel($0) }
                        ))
                    }
                    .controlSize(.small)
                    .frame(maxWidth: 305)
                }
                if !store.watches.isEmpty { PanelWatchPicker() }
                if store.panelWatch != nil {
                    Button { choosingPhoto = true } label: {
                        Label(
                            store.displayedWatchImageFilename == nil ? "Choose your photo…" : "Change photo…",
                            systemImage: "photo"
                        )
                    }
                    .buttonStyle(.ghost)
                    .controlSize(.regular)
                    .help("The sanitized copy stays on this Mac and contains no metadata")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .background(
            RadialGradient(colors: [Color.primary.opacity(0.05), .clear], center: .center, startRadius: 40, endRadius: 320)
        )
    }

    // MARK: Metrics

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                eyebrow: "Status",
                title: store.isConnected ? store.phaseTitle : (store.displayedLastSeen == nil ? "Saved watch" : "Last saved reading"),
                detail: store.isConnected
                    ? "changes apply immediately"
                    : (store.displayedLastSeen == nil ? "details will appear after pairing" : "available without reconnecting")
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                StatTile(icon: "battery.100percent", label: "Battery", value: store.displayedBattery.map { "\($0) %" } ?? "—",
                         progress: store.displayedBattery.map { Double($0) / 100 }, tint: (store.displayedBattery ?? 100) > 30 ? Theme.good : Theme.warn)
                StatTile(icon: "thermometer.medium", label: "Temperature", value: store.displayedTemperature.map { "\($0) °C" } ?? "—")
                StatTile(icon: "globe.europe.africa.fill", label: "Home city", value: store.displayedHomeCity.map { $0.capitalized } ?? "—")
                StatTile(icon: "clock.badge.checkmark", label: "Time sent", value: store.displayedLastTimeSync.map { Formatters.dateTime.string(from: $0) } ?? "—")
                StatTile(icon: "dot.radiowaves.left.and.right", label: "Last connection", value: store.displayedLastSeen.map { Formatters.dateTime.string(from: $0) } ?? "—")
                StatTile(icon: "timer", label: "Timer", value: store.displayedTimerSeconds.map { Formatters.duration($0) } ?? "—")
            }
            if store.phase == .unauthorized {
                Button("Open Bluetooth Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.accent)
            }
        }
    }

    // MARK: Gestures

    private var gestures: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(eyebrow: "Computer actions", title: "Watch gestures", detail: "click a row to change its action")
            VStack(spacing: 8) {
                ForEach(WatchButtonEvent.configurable) { event in
                    GestureRow(event: event) { editingEvent = event }
                }
            }
        }
    }

    private var pending: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(eyebrow: "Pending", title: "Will be sent on the next full connection")
            Tile(padding: 8) {
                VStack(spacing: 2) {
                    ForEach(store.pending) { item in
                        HStack {
                            Image(systemName: "tray.and.arrow.up.fill").foregroundStyle(Theme.warn)
                            Text(item.summary).font(.system(size: 13)).foregroundStyle(Theme.text)
                            Spacer()
                            Button { store.discardPending(item.id) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(Theme.text3).help("Discard")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

/// Chooses the Dashboard watch: an explicit favorite or the most recently connected unit.
@MainActor
private struct PanelWatchPicker: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: store.favoriteWatchID == nil ? "clock.arrow.circlepath" : "star.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(store.favoriteWatchID == nil ? Theme.text3 : Theme.warn)
            Picker("Dashboard watch", selection: Binding<String?>(
                get: { store.favoriteWatchID },
                set: { store.setFavoriteWatch($0) }
            )) {
                Text("Most recently connected").tag(nil as String?)
                Divider()
                ForEach(store.watches) { watch in
                    Text(watch.title).tag(Optional(watch.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        .help("Keep a favorite on the Dashboard or follow the most recently connected watch")
    }
}

/// A metric with an icon, label, and large value.
@MainActor
struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    var progress: Double? = nil
    var tint: Color = Theme.accent

    var body: some View {
        Tile(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                if let progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surface3)
                            Capsule().fill(tint).frame(width: max(6, geo.size.width * progress))
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
    }
}

/// A watch gesture and its assigned action.
@MainActor
struct GestureRow: View {
    @Environment(WatchStore.self) private var store
    let event: WatchButtonEvent
    let onEdit: () -> Void
    @State private var hovering = false

    var body: some View {
        let action = store.config.action(for: event)
        let active = store.lastEvent == event && store.phase == .connected
        HStack(spacing: 14) {
            GestureBadge(event: event, highlighted: active, large: true)
                .frame(width: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text(event.gesture).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: action.kind.systemImage).font(.system(size: 12, weight: .semibold))
                Text(action.summary).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(action.kind == .none ? Theme.text3 : Theme.accent)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(action.kind == .none ? Theme.surface2 : Theme.accentSoft, in: Capsule())
            Button { store.testAction(for: event) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.ghost)
                .disabled(action.kind == .none)
                .help("Test the action now")
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(hovering ? Theme.surface2 : Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(active ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onEdit)
        .focusable()
        .onKeyPress(.return) {
            onEdit()
            return .handled
        }
        .onKeyPress(.space) {
            onEdit()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(event.title). Action: \(action.summary)")
        .accessibilityHint("Press to edit the action")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Edit action", onEdit)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Sheet for a single gesture.
@MainActor
struct ActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: WatchButtonEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionTitle(eyebrow: "Mac action", title: event.title)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.accent).keyboardShortcut(.defaultAction)
            }
            ActionEditor(event: event)
        }
        .padding(22)
        .frame(width: 560)
    }
}

/// Sheet shown after selecting a physical button in the watch diagram.
@MainActor
struct ButtonActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let position: WatchButtonPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionTitle(eyebrow: "Button \(position.letter)", title: position.events.isEmpty ? "No Bluetooth gesture" : "Mac actions")
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.accent).keyboardShortcut(.defaultAction)
            }
            if position.events.isEmpty {
                Tile {
                    Label("Only the lower C and D buttons start a connection with the Mac. A and B control the watch.", systemImage: "hand.raised")
                        .foregroundStyle(Theme.text2)
                }
            } else {
                ForEach(position.events) { event in ActionEditor(event: event) }
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}
