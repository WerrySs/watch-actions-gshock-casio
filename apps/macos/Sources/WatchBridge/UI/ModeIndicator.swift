import AppKit
import Observation
import SwiftUI

@MainActor
private final class ModePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Optional click-through HUD in the primary screen's usable area, not in the camera/menu bar.
/// Event-driven Observation updates: no polling, keyboard listeners or screen recording.
@MainActor
final class ModeIndicatorController: NSObject {
    private weak var store: WatchStore?
    private var panel: ModePanel?

    func start(_ store: WatchStore) {
        guard self.store == nil else { return }
        self.store = store
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        observe()
    }
    private func observe() {
        withObservationTracking { updatePanel() } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }
    @objc private func screenChanged() { updatePanel() }

    static func frame(in visible: CGRect) -> CGRect {
        let width = min(196, max(0, visible.width - 24))
        let height = min(32, max(0, visible.height - 16))
        return CGRect(x: visible.midX - width / 2, y: visible.maxY - height - 8, width: width, height: height)
    }
    private func updatePanel() {
        guard let store else { panel?.orderOut(nil); return }
        // Read all display dependencies inside withObservationTracking, including mode changes.
        let enabled = store.config.showModeIndicator
        let layer = store.panelActionLayer
        let name = store.config.name(for: layer)
        let color = store.config.color(for: layer)
        let connected = store.isConnected
        let safe = store.storageWarning == nil
        let hasWatch = store.panelWatch != nil
        guard enabled, safe, hasWatch, let screen = NSScreen.screens.first else { panel?.orderOut(nil); return }
        if panel == nil {
            let p = ModePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.level = .floating; p.hidesOnDeactivate = false; p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.isReleasedWhenClosed = false
            panel = p
        }
        panel?.contentView = NSHostingView(rootView: ModeIndicatorView(name: name, color: color, connected: connected))
        panel?.setFrame(Self.frame(in: screen.visibleFrame), display: true)
        panel?.orderFrontRegardless()
    }
}

struct ModeIndicatorView: View {
    let name: String
    let color: String
    var connected = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: connected ? "applewatch.radiowaves.left.and.right" : "applewatch")
                .font(.system(size: 17, weight: .medium))
            Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.tail)
        }.foregroundStyle(ModeStyle.color(color)).padding(.horizontal, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dashboard watch action mode: \(name)")
    }
}
