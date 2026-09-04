import SwiftUI

@MainActor
struct RemindersView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(eyebrow: "Reminders", title: "Text on the watch display",
                                 detail: "\(store.reminders.filter { $0.enabled && !$0.watchTitle.isEmpty }.count) of 5 active · 18 ASCII characters")
                    Spacer()
                    if !store.remindersRead {
                        Label("Hold C for 3 seconds to read reminders", systemImage: "info.circle")
                            .font(.system(size: 12)).foregroundStyle(Theme.warn)
                    }
                }
                ForEach(store.reminders) { reminder in
                    ReminderCard(original: reminder)
                }
            }
            .padding(26)
        }
    }
}

@MainActor
struct ReminderCard: View {
    @Environment(WatchStore.self) private var store
    let original: Reminder
    @State private var draft: Reminder
    @State private var dirty = false

    init(original: Reminder) {
        self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        Tile(padding: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("\(draft.slot)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(draft.enabled ? Theme.accent : Theme.text3, in: RoundedRectangle(cornerRadius: 5))
                        Text(draft.enabled ? "Active" : "Off")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(draft.enabled ? Theme.accent : Theme.text3)
                    }
                    LCDText(text: draft.watchTitle, size: 14)
                    Text(schedule).font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 210, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    DarkField(placeholder: "Text shown on the watch", text: $draft.title)
                        .onChange(of: draft.title) {
                            if draft.title.count > 40 { draft.title = String(draft.title.prefix(40)) }
                        }
                    HStack(spacing: 14) {
                        FieldLabel(label: "From") {
                            DatePicker("", selection: $draft.start, displayedComponents: .date).labelsHidden().datePickerStyle(.field)
                        }
                        FieldLabel(label: "Until") {
                            DatePicker("", selection: $draft.end, in: draft.start..., displayedComponents: .date).labelsHidden().datePickerStyle(.field)
                        }
                        FieldLabel(label: "Repeat") {
                            Picker("", selection: $draft.repeatMode) {
                                ForEach(RepeatMode.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden().frame(width: 170)
                        }
                        if draft.repeatMode == .weekly {
                            FieldLabel(label: "Days") {
                                HStack(spacing: 4) {
                                    ForEach(Weekday.allCases) { day in
                                        DayChip(day: day, on: dayBinding(day))
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 10) {
                        Toggle(isOn: $draft.enabled) { EmptyView() }.toggleStyle(.accentSwitch)
                        Text(draft.enabled ? "Shown on the watch" : "Saved but disabled").font(.system(size: 12)).foregroundStyle(Theme.text2)
                        Spacer()
                        if dirty { Text("Unsaved").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.warn) }
                        Button("Clear") {
                            var empty = Reminder(slot: draft.slot)
                            empty.enabled = false
                            draft = empty
                            Task { await store.save(.reminder(empty)); dirty = false }
                        }
                        .buttonStyle(.danger)
                        Button {
                            Task { await store.save(.reminder(draft)); dirty = false }
                        } label: { Label("Save to watch", systemImage: "arrow.up.circle.fill") }
                            .buttonStyle(.accent)
                            .disabled(!dirty || (draft.repeatMode == .weekly && draft.days.isEmpty))
                    }
                }
            }
        }
        .onChange(of: draft) { dirty = draft != original }
        .onChange(of: draft.start) { if draft.end < draft.start { draft.end = draft.start } }
        .onChange(of: original) { if !dirty { draft = original } }
    }

    private var schedule: String {
        let f = Formatters.shortDate
        switch draft.repeatMode {
        case .never:
            return Calendar.current.isDate(draft.start, inSameDayAs: draft.end) || draft.end < draft.start
                ? "On \(f.string(from: draft.start))"
                : "From \(f.string(from: draft.start)) to \(f.string(from: draft.end))"
        case .weekly:
            let days = draft.days.sorted().map(\.short).joined(separator: " ")
            return "Every week: \(days.isEmpty ? "no days" : days)"
        case .monthly: return "Every month on day \(Calendar.current.component(.day, from: draft.start))"
        case .yearly: return "Every year on \(f.string(from: draft.start).dropLast(4))"
        }
    }

    private func dayBinding(_ day: Weekday) -> Binding<Bool> {
        Binding(get: { draft.days.contains(day) },
                set: { on in if on { draft.days.insert(day) } else { draft.days.remove(day) } })
    }
}

/// Accessible weekday selector.
@MainActor
struct DayChip: View {
    let day: Weekday
    @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            Text(day.short)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(on ? Color.white : Theme.text2)
                .frame(width: 26, height: 26)
                .background(on ? Theme.accent : Theme.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(on ? .clear : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(day.name)
        .accessibilityLabel(day.name)
        .accessibilityValue(on ? "Selected" : "Not selected")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
