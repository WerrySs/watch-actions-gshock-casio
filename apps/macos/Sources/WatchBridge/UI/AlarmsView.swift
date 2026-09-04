import SwiftUI

@MainActor
struct AlarmsView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(eyebrow: "Alarms", title: "Five watch alarms",
                                 detail: "\(store.alarms.filter(\.enabled).count) active")
                    Spacer()
                    if !store.alarmsRead {
                        Label("Hold C for 3 seconds to read alarms", systemImage: "info.circle")
                            .font(.system(size: 12)).foregroundStyle(Theme.warn)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(store.alarms) { alarm in
                        AlarmRow(original: alarm)
                    }
                }
                Text("The hourly signal makes the watch beep on the hour and is configured in alarm 1.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
            .padding(26)
        }
    }
}

@MainActor
struct AlarmRow: View {
    @Environment(WatchStore.self) private var store
    let original: Alarm
    @State private var draft: Alarm
    @State private var dirty = false

    init(original: Alarm) {
        self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        Tile(padding: 14) {
            HStack(spacing: 18) {
                Text("\(draft.number)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(draft.enabled ? Theme.accent : Theme.text3, in: RoundedRectangle(cornerRadius: 5))
                LCDText(text: draft.timeText, size: 22)
                    .opacity(draft.enabled ? 1 : 0.55)
                DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                Toggle(isOn: $draft.enabled) { EmptyView() }.toggleStyle(.accentSwitch)
                Text(draft.enabled ? "Active" : "Off").font(.system(size: 12)).foregroundStyle(Theme.text2).frame(width: 60, alignment: .leading)
                if draft.number == 1 {
                    Toggle(isOn: $draft.hourlyChime) {
                        Label("Hourly signal", systemImage: "bell.badge").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                    .toggleStyle(.accentSwitch)
                }
                Spacer()
                if dirty { Text("Unsaved").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.warn) }
                Button {
                    Task { await store.save(.alarm(draft)); dirty = false }
                } label: { Label("Save", systemImage: "arrow.up.circle.fill") }
                    .buttonStyle(.accent)
                    .disabled(!dirty)
            }
        }
        .onChange(of: draft) { dirty = draft != original }
        .onChange(of: original) { if !dirty { draft = original } }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: draft.hour, minute: draft.minute, second: 0, of: .now) ?? .now },
            set: { date in
                draft.hour = Calendar.current.component(.hour, from: date)
                draft.minute = Calendar.current.component(.minute, from: date)
            })
    }
}
