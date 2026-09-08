import SwiftUI
import AppKit

enum ModeStyle {
    static func menuSymbol(connected: Bool, color name: String) -> NSImage {
        let base = NSImage(systemSymbolName: connected ? "applewatch.radiowaves.left.and.right" : "applewatch", accessibilityDescription: "WatchBridge") ?? NSImage()
        let image = base.withSymbolConfiguration(.init(paletteColors: [NSColor(color(name))])) ?? base
        image.isTemplate = false
        return image
    }
    static func color(_ name: String) -> Color {
        switch name {
        case "purple": Color(red: 0.73, green: 0.54, blue: 1)
        case "green": Color(red: 0.34, green: 0.85, blue: 0.59)
        case "orange": Color(red: 1, green: 0.71, blue: 0.37)
        case "pink": Color(red: 1, green: 0.51, blue: 0.72)
        case "cyan": Color(red: 0.33, green: 0.84, blue: 0.91)
        case "yellow": Color(red: 0.91, green: 0.84, blue: 0.42)
        case "red": Color(red: 1, green: 0.50, blue: 0.50)
        default: Color(red: 0.29, green: 0.62, blue: 1)
        }
    }
}

@MainActor
struct ActionLayerControls: View {
    @Environment(WatchStore.self) private var store
    @State private var showNew = false
    @State private var showEdit = false
    @State private var confirmDelete = false
    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    SectionTitle(eyebrow: "Action modes", title: "A set of actions for every task", detail: "Select a card to edit. The watch button cycles through this order.")
                    Spacer()
                    Button { showNew = true } label: { Label("New mode", systemImage: "plus") }
                        .buttonStyle(.accent).disabled(store.config.profiles.count >= 100)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(store.config.layers.enumerated()), id: \.element) { index, layer in
                            let color = ModeStyle.color(store.config.color(for: layer))
                            Button { store.editingLayer = layer } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Circle().fill(color).frame(width: 8, height: 8)
                                        Text("\(index + 1)").font(.caption).foregroundStyle(Theme.text2)
                                        Spacer()
                                        if store.panelActionLayer == layer { Text("ACTIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(color) }
                                    }
                                    Text(store.config.name(for: layer)).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                                    Text(store.editingLayer == layer ? "Editing actions below" : "Click to edit").font(.caption).foregroundStyle(Theme.text2)
                                }.padding(13).frame(width: 168, alignment: .leading)
                                    .background(color.opacity(store.editingLayer == layer ? 0.15 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(store.editingLayer == layer ? color : Theme.strokeStrong, lineWidth: store.editingLayer == layer ? 2 : 1))
                            }.buttonStyle(.plain).accessibilityLabel("Edit \(store.config.name(for: layer)) mode")
                            Image(systemName: index == store.config.layers.count - 1 ? "arrow.uturn.backward" : "chevron.right")
                                .font(.caption).foregroundStyle(Theme.text3).accessibilityLabel(index == store.config.layers.count - 1 ? "Back to Normal" : "Next mode")
                        }
                    }.padding(.vertical, 3)
                }
                HStack {
                    Picker("Next mode button", selection: Binding(get: { store.config.switchEvent?.rawValue ?? "" }, set: { store.setModeSwitch(WatchButtonEvent(rawValue: $0)) })) {
                        Text("Disabled").tag("")
                        ForEach([WatchButtonEvent.find, .rightShort, .leftLong]) { event in Text(event.display).tag(event.rawValue) }
                    }.frame(width: 230)
                    Spacer()
                    if store.editingLayer != .normal {
                        Button("Name & color…") { showEdit = true }.buttonStyle(.ghost)
                        Button { store.moveMode(store.editingLayer, by: -1) } label: { Image(systemName: "arrow.left") }
                            .help("Move earlier in the cycle").disabled(store.config.profiles.first?.id == store.editingLayer.id)
                        Button { store.moveMode(store.editingLayer, by: 1) } label: { Image(systemName: "arrow.right") }
                            .help("Move later in the cycle").disabled(store.config.profiles.last?.id == store.editingLayer.id)
                        Button { confirmDelete = true } label: { Image(systemName: "trash") }.help("Delete this mode")
                    }
                    Button("Reset to Normal") { store.resetActionModes() }.buttonStyle(.ghost)
                }
                HStack {
                    Toggle("Floating mode indicator", isOn: Binding(get: { store.config.showModeIndicator }, set: { store.setModeIndicator($0) }))
                    Spacer()
                    Label("Dashboard watch · \(store.config.name(for: store.panelActionLayer))", systemImage: "applewatch")
                        .foregroundStyle(ModeStyle.color(store.config.color(for: store.panelActionLayer)))
                }.font(.callout)
                Text("Editing does not activate a mode. The reserved gesture cycles all modes; each trusted watch has its own active mode. Mode order changes and app restart reset to Normal. AUTO stays Normal; watch syncing is unchanged.")
                    .font(.caption).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showNew) { ModeDetailsEditor(layer: nil) }
        .sheet(isPresented: $showEdit) { ModeDetailsEditor(layer: store.editingLayer) }
        .confirmationDialog("Delete \(store.config.name(for: store.editingLayer)) and its actions?", isPresented: $confirmDelete) {
            Button("Delete mode", role: .destructive) { store.deleteMode(store.editingLayer) }
        } message: { Text("This cannot be undone. Other modes are kept and all watches return to Normal.") }
    }
}

@MainActor
private struct ModeDetailsEditor: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let layer: ActionLayer?
    @State private var name = ""
    @State private var color = "purple"
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(eyebrow: "Action modes", title: layer == nil ? "Create a mode" : "Name & color", detail: "Use a name you can recognize at a glance, such as Music or Presentation.")
            TextField("Mode name", text: $name).textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                ForEach(ActionsConfig.colors, id: \.self) { option in
                    Button { color = option } label: {
                        Circle().fill(ModeStyle.color(option)).frame(width: 30, height: 30)
                            .overlay { if color == option { Image(systemName: "checkmark").foregroundStyle(.black).fontWeight(.bold) } }
                    }.buttonStyle(.plain).accessibilityLabel(option.capitalized).accessibilityAddTraits(color == option ? .isSelected : [])
                }
            }
            Text("The color is used in mode cards, the menu bar and the optional floating indicator. Mode names remain visible so color is not the only cue.").font(.caption).foregroundStyle(Theme.text2)
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button(layer == nil ? "Create mode" : "Save") {
                    if let layer { store.updateMode(layer, name: name, color: color) }
                    else { store.addMode(named: name); store.updateMode(store.editingLayer, name: name, color: color) }
                    dismiss()
                }.buttonStyle(.accent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 40)
            }
        }.padding(24).frame(width: 430)
            .onAppear { if let layer { name = store.config.name(for: layer); color = store.config.color(for: layer) } }
    }
}
