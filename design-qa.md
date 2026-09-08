# Design validation scope

## macOS

The committed images in `docs/screenshots/` are **offscreen full-window previews** of the SwiftUI views with sample data, not screenshots proving interaction or a hardware connection. They include navigation and the title bar. Bluetooth and real saved-state access are disabled in snapshot mode. The macOS 15 CI runner produced these images; desktop vibrancy, native glyph tint and active-window styling cannot be fully represented by the offscreen renderer.

The intended layout retains the reference's prominent watch image, cached status and two-column action grid. A neutral shared watch PNG replaces manufacturer imagery; both Dashboard and button guide use it. Action cards reserve common header/control/value/help regions.

The accepted images were generated in [CI run 34106828540](https://github.com/WerrySs/watch-actions-gshock-casio/actions/runs/34106828540), from commit `44d413b`, and inspected before inclusion. Default previews are 1240 × 800; the full Actions page uses 1240 × 1400. The same run includes 1080 × 700 minimum-size views for review.

1. **Dashboard:** the default-size view fits saved readings and four gesture rows alongside the watch and sidebar. Identity controls are consolidated. At minimum size the content scrolls and long action labels truncate; interactive keyboard/tooltips still need checking.
2. **Actions:** the full-page view shows four equal-height cards with aligned headers/selectors and the A/B/C/D guide. The default/minimum window scrolls inside the content, leaving navigation in place.
3. **My Watches:** two sample units fit at default size, with paired/trusted and registered/not-paired states distinguished. Model, local-photo, favorite and explicit-link controls remain visible.

Source screenshots supplied by the owner are not committed: they include unrelated notifications and third-party product photography. The README uses only generated sample data and the project's neutral illustration, not an official model photograph.

The Dashboard now uses the watch name as the watch selector, with model/photo/favorite controls grouped in one options menu. Saved readings use secondary text rather than an amber warning chip. Photo import captures the intended watch ID before opening the file chooser. A regression test checks that choosing a favorite and editing its model never retargets queued physical-watch writes.

`--snapshot <directory> --full-window --only watch` renders the real `ContentView` including navigation. Use `--full-page --only actions` for the taller Actions view. CI produces these and minimum-size renders as a separate review artifact; inspect them before replacing README images. The fixture preserves the requested size even on a smaller runner desktop. macOS 26's offscreen glass compositor produced blank sidebar/toolbar regions locally, so those outputs were rejected. Live Computer Use inspection was unavailable because of a client/server version mismatch; it requires a client relaunch. No interactive audit pass is claimed.

## Action-layer update — September 8, 2026

The macOS target/protection banner now participates in the detail column's layout below the toolbar, leaving page headings unobscured. The Dashboard halo reaches full transparency inside the image bounds instead of using an oversized blurred texture. The Actions editor adds distinct active/edited layers and keeps common card heights; its visual keyboard has six key rows, explicit modifier selection, a repeat count and a safe-test notice.

Local sample-data renders were inspected for the keyboard, layer cards, Dashboard and default/minimum-size settings banner. The banner/content gap and halo fade are visible; macOS 26 still leaves offscreen sidebar/toolbar glass blank, so those full-window local images are not publication assets. CI renders keyboard, default/minimum settings, and full-page action-layer fixtures for review. Full-page fixtures are now 1240 × 1680 (or 1080 wide with `--minimum-size`) so the new controls do not truncate the time-sync section. Use `--action-layers --only actions` to select the new sample configuration and `--only keyboard` for the standalone keyboard.

## Windows

Slint defines a minimum 1080 × 700 window, two real cards per action row, equal card heights and common header/selector regions. Native CI can validate compilation, tests and startup. It does **not** establish that Mica, scaling or every interaction works on an end-user Windows desktop.

## Interactive checks still required

On physical macOS and Windows installations:

- Navigate every page at default and minimum window sizes.
- Test keyboard focus, screen-reader labels and 100/150/200% display scaling.
- Confirm selectors, optional action fields, Test buttons and result messages remain usable.
- Check favorite/last-connected behavior, explicit linking and trust with two watches.
- Confirm cancellation, reconnects, sleep/wake, Bluetooth permissions and missing-adapter behavior.
- Check Mica on supported Windows 11 versions and the fallback on Windows 10.

No blanket visual/accessibility pass or real-device certification is claimed. Record evidence through the hardware issue template and update [Compatibility](docs/COMPATIBILITY.md) only after reproducible tests.
