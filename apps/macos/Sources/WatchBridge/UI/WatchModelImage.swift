import AppKit
import SwiftUI

/// Shows the local photo selected for a unit, or the project's neutral bundled illustration.
/// WatchBridge never downloads manufacturer photography.
@MainActor
struct WatchModelImage: View {
    let model: String
    var imageFilename: String? = nil

    private var localImage: NSImage? { WatchImageStore.image(named: imageFilename) }

    var body: some View {
        Group {
            if let localImage {
                Image(nsImage: localImage)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Local photo of \(SavedWatch.displayName(for: model))")
            } else if let placeholder = WatchImageStore.defaultImage() {
                Image(nsImage: placeholder)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Neutral watch illustration; \(SavedWatch.displayName(for: model)) has no local photo")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 88, weight: .thin))
                    Text(model)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(Theme.text3)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(SavedWatch.displayName(for: model)) without a local photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
