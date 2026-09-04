import AppKit
import SwiftUI

private struct SnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var snapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}

/// Native visual system: semantic colors, the user's accent, and translucent surfaces.
enum Theme {
    static let bg = Color.clear
    static let rail = Color.clear
    static let surface = Color.primary.opacity(0.045)
    static let surface2 = Color.primary.opacity(0.075)
    static let surface3 = Color.primary.opacity(0.13)
    static let stroke = Color.primary.opacity(0.08)
    static let strokeStrong = Color.primary.opacity(0.16)
    static let accent = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.18)
    static let good = Color.green
    static let warn = Color.orange
    static let bad = Color.red
    static let lcd = Color(red: 0.62, green: 0.68, blue: 0.56)
    static let lcdInk = Color(red: 0.10, green: 0.12, blue: 0.10)
    static let text = Color.primary
    static let text2 = Color.secondary
    static let text3 = Color.secondary.opacity(0.78)

    static func statusColor(_ phase: WatchStore.Phase) -> Color {
        switch phase {
        case .connected: good
        case .waiting: warn
        case .starting: text3
        default: bad
        }
    }
}

/// System material that lets the desktop tint the window like a native Mac app.
@MainActor
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

// MARK: - Containers

/// Translucent card with a subtle border.
@MainActor
struct Tile<Content: View>: View {
    var padding: CGFloat = 16
    var fill: Color = Theme.surface
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// Section heading with a quiet eyebrow and primary title.
@MainActor
struct SectionTitle: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Gesture label (CNCT, TIME, FIND, AUTO) in the current accent color.
@MainActor
struct GestureBadge: View {
    let event: WatchButtonEvent
    var highlighted = false
    var large = false

    var body: some View {
        Text(event.display)
            .font(.system(size: large ? 11 : 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, large ? 8 : 6).padding(.vertical, large ? 4 : 3)
            .background(highlighted ? Theme.accent : Theme.accentSoft, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(highlighted ? Color.white : Theme.accent)
            .fixedSize()
    }
}

/// Text styled like the watch LCD.
@MainActor
struct LCDText: View {
    let text: String
    var size: CGFloat = 14

    var body: some View {
        Text(text.isEmpty ? "— — —" : text)
            .font(.system(size: size, weight: .heavy, design: .monospaced))
            .foregroundStyle(text.isEmpty ? Theme.lcdInk.opacity(0.35) : Theme.lcdInk)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Theme.lcd, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.black.opacity(0.3), lineWidth: 1))
    }
}

/// Status chip with a colored indicator.
@MainActor
struct StatusChip: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.surface2, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - Native buttons and switches

/// Native prominent button with a deterministic snapshot fallback.
struct AdaptiveProminentStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.snapshotRendering) private var snapshotRendering
    func makeBody(configuration: Configuration) -> some View {
        if snapshotRendering {
            Button(action: configuration.trigger) {
                configuration.label
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Button(action: configuration.trigger) { configuration.label }
                .buttonStyle(.borderedProminent)
                .opacity(enabled ? 1 : 0.48)
        }
    }
}

/// Native bordered button with a deterministic snapshot fallback.
struct AdaptiveBorderedStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.snapshotRendering) private var snapshotRendering
    func makeBody(configuration: Configuration) -> some View {
        if snapshotRendering {
            Button(action: configuration.trigger) {
                configuration.label
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(enabled ? 1 : 0.4))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.surface3, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Button(action: configuration.trigger) { configuration.label }
                .buttonStyle(.bordered)
                .opacity(enabled ? 1 : 0.48)
        }
    }
}

extension PrimitiveButtonStyle where Self == AdaptiveProminentStyle {
    static var accent: AdaptiveProminentStyle { AdaptiveProminentStyle() }
}
extension PrimitiveButtonStyle where Self == AdaptiveBorderedStyle {
    static var ghost: AdaptiveBorderedStyle { AdaptiveBorderedStyle() }
}

struct DangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.bad)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.bad.opacity(configuration.isPressed ? 0.22 : 0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(enabled ? 1 : 0.48)
    }
}
extension ButtonStyle where Self == DangerButtonStyle { static var danger: DangerButtonStyle { DangerButtonStyle() } }

/// Native switch with a deterministic snapshot fallback.
struct AdaptiveSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.snapshotRendering) private var snapshotRendering

    func makeBody(configuration: Configuration) -> some View {
        if snapshotRendering {
            Button { configuration.isOn.toggle() } label: {
                HStack(spacing: 8) {
                    configuration.label
                    ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                        Capsule().fill(configuration.isOn ? Color.accentColor : Theme.surface3)
                        Circle().fill(.white).frame(width: 13, height: 13).padding(2)
                    }
                    .frame(width: 30, height: 17)
                }
                .opacity(enabled ? 1 : 0.45)
            }
            .buttonStyle(.plain)
        } else {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

extension ToggleStyle where Self == AdaptiveSwitchStyle {
    static var accentSwitch: AdaptiveSwitchStyle { AdaptiveSwitchStyle() }
}

// MARK: - Fields

/// Native text field.
@MainActor
struct DarkField: View {
    @Environment(\.snapshotRendering) private var snapshotRendering
    let placeholder: String
    @Binding var text: String
    var font: Font = .system(size: 13)

    var body: some View {
        if snapshotRendering {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(font)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(font)
        }
    }
}

/// Small label above a control.
@MainActor
struct FieldLabel<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }
}

/// Labeled switch row.
@MainActor
struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent).frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13)).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
            Toggle(isOn: $isOn) { EmptyView() }.toggleStyle(.accentSwitch)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
