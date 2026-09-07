import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct WatchesView: View {
    @Environment(WatchStore.self) private var store
    @State private var showingRegistration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    SectionTitle(
                        eyebrow: "Local collection",
                        title: "My Watches",
                        detail: store.watches.isEmpty
                            ? "register one now or let it appear after connecting"
                            : "\(store.watches.count) saved \(store.watches.count == 1 ? "watch" : "watches") on this Mac"
                    )
                    Spacer()
                    Button { showingRegistration = true } label: {
                        Label("Add watch", systemImage: "plus")
                    }
                    .buttonStyle(.accent)
                    .controlSize(.large)
                }

                if store.watches.isEmpty {
                    PreferredModelCard()
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(store.watches) { watch in
                            SavedWatchCard(watch: watch, isCurrent: watch.id == store.currentWatchID)
                        }
                    }
                }

                Label(
                    "Photos are processed and stored only on this Mac. WatchBridge removes metadata such as EXIF and GPS and never uploads them.",
                    systemImage: "hand.raised.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 2)
            }
            .padding(26)
        }
        .sheet(isPresented: $showingRegistration) { RegisterWatchSheet() }
    }
}

@MainActor
private struct PreferredModelCard: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        Tile(padding: 20) {
            HStack(spacing: 30) {
                WatchModelImage(model: store.preferredModel)
                    .frame(width: 190, height: 250)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Start your collection")
                        .font(.system(size: 19, weight: .semibold))
                    Text("Register a model before pairing it. You can add your own photo later and choose which watch appears on the Dashboard.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    FieldLabel(label: "Expected model") {
                        ModelPicker(selection: Binding(
                            get: { store.preferredModel },
                            set: { store.setPreferredModel($0) }
                        ))
                    }
                    .frame(maxWidth: 360)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
        }
    }
}

@MainActor
private struct SavedWatchCard: View {
    @Environment(WatchStore.self) private var store
    let watch: SavedWatch
    let isCurrent: Bool
    @State private var choosingPhoto = false

    var body: some View {
        Tile(padding: 18) {
            HStack(alignment: .top, spacing: 22) {
                ZStack(alignment: .bottom) {
                    WatchModelImage(model: watch.effectiveModel, imageFilename: watch.imageFilename)
                        .frame(width: 160, height: 210)
                    Text(watch.imageFilename == nil ? "ILLUSTRATION" : "LOCAL PHOTO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(watch.imageFilename == nil ? Theme.text2 : Theme.good)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(watch.title)
                                .font(.system(size: 18, weight: .semibold))
                            if watch.title != watch.effectiveDisplayName {
                                Text(watch.effectiveDisplayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if isCurrent { statusBadge("LATEST", color: Theme.accent) }
                        if watch.connectionCount == 0 { statusBadge("NOT PAIRED", color: Theme.warn) }
                    }

                    if let variant = WatchModelVariant.matching(watch.effectiveModel) {
                        FieldLabel(label: "Exact model") {
                            ModelPicker(selection: Binding(
                                get: { WatchModelVariant(rawValue: watch.effectiveModel)?.rawValue ?? variant.rawValue },
                                set: { store.setExactModel($0, for: watch.id) }
                            ))
                        }
                        .controlSize(.regular)
                    } else {
                        Text("Registered model: \(watch.effectiveModel)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.text2)
                    }

                    HStack(spacing: 18) {
                        watchDetail(watch.connectionCount == 0 ? "Added" : "First connection", date: watch.firstSeen)
                        if watch.connectionCount > 0 { watchDetail("Last connection", date: watch.lastSeen) }
                    }

                    HStack(spacing: 14) {
                        Label("\(watch.connectionCount) connections", systemImage: "link")
                        if let battery = watch.lastBattery {
                            Label("\(battery) %", systemImage: "battery.100percent")
                        }
                        if let temperature = watch.lastTemperature {
                            Label("\(temperature) °C", systemImage: "thermometer.medium")
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        if watch.manuallyRegistered == true, watch.connectionCount == 0 {
                            Menu("Link physical watch") {
                                ForEach(store.watches.filter { $0.connectionCount > 0 && $0.manuallyRegistered != true && RustCore.supports(model: $0.model) }) { physical in
                                    Button("\(physical.title) · \(Formatters.dateTime.string(from: physical.lastSeen))") {
                                        store.linkRegistration(watch.id, to: physical.id)
                                    }
                                }
                            }
                            .help("Explicitly choose the physical unit represented by this saved registration")
                            Text("Actions available after linking")
                                .font(.system(size: 10)).foregroundStyle(Theme.text3)
                        } else {
                        Toggle("Allow actions on this Mac", isOn: Binding(
                            get: { watch.canRunMacActions },
                            set: { store.setAllowsMacActions($0, for: watch.id) }
                        ))
                        .toggleStyle(.accentSwitch)
                        .disabled(watch.connectionCount == 0)
                        .help(watch.connectionCount == 0
                            ? "Pair this physical unit first"
                            : "Trust this watch to run configured actions")
                        if !watch.canRunMacActions {
                            Text(watch.connectionCount == 0 ? "Available after pairing" : "Blocked for safety")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.text3)
                        }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 10) {
                    Button { choosingPhoto = true } label: {
                        Label(watch.imageFilename == nil ? "Choose photo…" : "Change photo…", systemImage: "photo")
                            .frame(minWidth: 118)
                    }
                    .buttonStyle(.ghost)
                    .controlSize(.large)

                    if watch.imageFilename != nil {
                        Button { store.removeWatchImage(for: watch.id) } label: {
                            Label("Remove photo", systemImage: "photo.badge.minus")
                                .frame(minWidth: 118)
                        }
                        .buttonStyle(.ghost)
                    }

                    Button { store.toggleFavorite(watch.id) } label: {
                        Label(
                            store.favoriteWatchID == watch.id ? "On Dashboard" : "Show on Dashboard",
                            systemImage: store.favoriteWatchID == watch.id ? "star.fill" : "star"
                        )
                        .frame(minWidth: 118)
                    }
                    .buttonStyle(.ghost)
                    .tint(store.favoriteWatchID == watch.id ? Theme.warn : Theme.accent)
                    .help(store.favoriteWatchID == watch.id
                        ? "This is the Dashboard favorite"
                        : "Always show this watch on the Dashboard")

                    Spacer(minLength: 0)
                }
                .frame(minWidth: 150, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .fileImporter(
            isPresented: $choosingPhoto,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.importWatchImage(from: url, for: watch.id)
            }
        }
    }

    private func watchDetail(_ label: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(Formatters.dateTime.string(from: date)).monospacedDigit().foregroundStyle(Theme.text)
        }
        .font(.system(size: 11))
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

@MainActor
struct ModelPicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Exact model", selection: $selection) {
            ForEach(WatchModelVariant.allCases) { variant in
                Text(variant.pickerTitle).tag(variant.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityHint("Saves the exact model variant; photography is selected separately")
    }
}

@MainActor
private struct RegisterWatchSheet: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case catalog, other
        var id: String { rawValue }
        var title: String { self == .catalog ? "GW-B5600 family" : "Exact regional variant" }
    }

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .catalog
    @State private var variant = WatchModelVariant.generic.rawValue
    @State private var customModel = ""
    @State private var nickname = ""

    private var model: String { kind == .catalog ? variant : customModel }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                SectionTitle(
                    eyebrow: "Local collection",
                    title: "Add a watch",
                    detail: "it does not need to be connected or paired"
                )
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.ghost)
            }

            HStack(spacing: 26) {
                WatchModelImage(model: model.isEmpty ? WatchModelVariant.generic.rawValue : model)
                    .frame(width: 175, height: 235)

                VStack(alignment: .leading, spacing: 14) {
                    Picker("Model type", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if kind == .catalog {
                        FieldLabel(label: "Exact model") {
                            ModelPicker(selection: $variant)
                        }
                    } else {
                        FieldLabel(label: "Watch model") {
                            DarkField(placeholder: "For example, GW-B5600BP-1ER", text: $customModel)
                        }
                    }

                    FieldLabel(label: "Optional nickname") {
                        DarkField(placeholder: "For example, Daily watch", text: $nickname)
                    }

                    Label("After adding it, you can select your own photo from its card.", systemImage: "photo.badge.plus")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Add to My Watches") {
                    if store.registerWatch(model: model, nickname: nickname) != nil { dismiss() }
                }
                .buttonStyle(.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 690)
    }
}
