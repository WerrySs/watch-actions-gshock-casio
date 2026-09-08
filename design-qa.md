# Design validation scope

## macOS

The committed images in `docs/screenshots/` are **offscreen full-window previews** of the SwiftUI views with sample data, not screenshots proving interaction or a hardware connection. They include navigation and the title bar. Bluetooth and real saved-state access are disabled in snapshot mode. The macOS 15 CI runner produced these images; desktop vibrancy, native glyph tint and active-window styling cannot be fully represented by the offscreen renderer.

The intended layout retains the reference's prominent watch image, cached status and two-column action grid. A neutral shared watch PNG replaces manufacturer imagery; both Dashboard and button guide use it. Action cards reserve common header/control/value/help regions.

The Actions and keyboard README images come from inspected [CI run 34215691461](https://github.com/WerrySs/watch-actions-gshock-casio/actions/runs/34215691461) fixtures at `104af5c`, showing named modes and the recorder. The same run includes minimum-width modes, expanded manual controls and the indicator. Dashboard remains the inspected [CI run 34200458420](https://github.com/WerrySs/watch-actions-gshock-casio/actions/runs/34200458420) fixture at `496794e`; My Watches remains [CI run 34106828540](https://github.com/WerrySs/watch-actions-gshock-casio/actions/runs/34106828540) at `44d413b`. Default previews are 1240 × 800; full Actions pages are 1240 × 1680, or 1080 wide at minimum size. These are representative layout previews; later help-text changes are reviewed in the CI artifacts.

1. **Dashboard:** the default-size view fits saved readings and four gesture rows alongside the watch and sidebar. Identity controls are consolidated. At minimum size the content scrolls and long action labels truncate; interactive keyboard/tooltips still need checking.
2. **Actions:** the full-page view shows numbered modes, four equal-height gesture cards with aligned headers/selectors, and a collapsible A/B/C/D guide. The default/minimum window scrolls inside the content, leaving navigation in place.
3. **My Watches:** two sample units fit at default size, with paired/trusted and registered/not-paired states distinguished. Model, local-photo, favorite and explicit-link controls remain visible.

Source screenshots supplied by the owner are not committed: they include unrelated notifications and third-party product photography. The README uses only generated sample data and the project's neutral illustration, not an official model photograph.

The Dashboard now uses the watch name as the watch selector, with model/photo/favorite controls grouped in one options menu. Saved readings use secondary text rather than an amber warning chip. Photo import captures the intended watch ID before opening the file chooser. A regression test checks that choosing a favorite and editing its model never retargets queued physical-watch writes.

`--snapshot <directory> --full-window --only watch` renders the real `ContentView` including navigation. Use `--full-page --only actions` for the taller Actions view. CI produces these and minimum-size renders as a separate review artifact; inspect them before replacing README images. The fixture preserves the requested size even on a smaller runner desktop. macOS 26's offscreen glass compositor produced blank sidebar/toolbar regions locally, so those outputs were rejected. Live Computer Use inspection was unavailable because of a client/server version mismatch; it requires a client relaunch. No interactive audit pass is claimed.

## Action-layer update — September 8, 2026

The first action-layer update placed the macOS target/protection banner in the detail column's layout below the toolbar, leaving page headings unobscured. The Dashboard halo reaches full transparency inside the image bounds instead of using an oversized blurred texture. That update added distinct active/edited layers and common card heights; its six-row visual keyboard has since been replaced by the recorder described below.

Local sample-data renders were inspected for the keyboard, layer cards, Dashboard and default/minimum-size settings banner. The banner/content gap and halo fade are visible; macOS 26 still leaves offscreen sidebar/toolbar glass blank, so those full-window local images are not publication assets. CI renders keyboard, default/minimum settings, and full-page action-layer fixtures for review. Full-page fixtures are now 1240 × 1680 (or 1080 wide with `--minimum-size`) so the new controls do not truncate the time-sync section. Use `--action-layers --only actions` to select the new sample configuration and `--only keyboard` for the standalone keyboard.

## Windows

Slint defines a minimum 1080 × 700 window, two real cards per action row, equal card heights and common header/selector regions. Native CI can validate compilation, tests and startup. It does **not** establish that Mica, scaling or every interaction works on an end-user Windows desktop.

The action-layer review adds a sample-data Slint renderer with no state loading, BLE or action callbacks. Local client-area renders caught clipped key labels/footer and unequal card widths/tall Test buttons; these were corrected with explicit bounds, padding and equal column widths. Oversized windows produced blank GPU readbacks, not evidence of a blank end-user app, so fixtures use default/minimum windows and scroll offsets instead. CI also rejects empty captures. On Windows the workflow produces PNG previews from BMP readbacks using the OS encoder, without adding a screenshot library or capturing the desktop/native frame. Review artifacts cover the Actions header, each card row and the keyboard at both widths; they are not Mica or input-delivery certification.

The first hosted capture attempt (CI 34202387610) failed after native tests and packaging, without renderer diagnostics from the GUI process. The workflow now captures sample-process stderr and builds an optional `software-preview` fixture tool, selecting Slint's CPU renderer for reproducible layout inspection without a hosted GPU requirement. Production archives are built/uploaded before that feature is enabled and keep their renderer unchanged. Do not use CPU captures to claim that the failed GPU path, interactive scaling or end-user GPU behavior was validated.

The native CPU fixtures in CI 34203617517 revealed a real system-theme mismatch: the app's custom surfaces are dark, but system-light widget labels could be black on dark backgrounds. MainWindow now selects the dark widget palette explicitly. CPU-only previews also show a thin diagonal gradient rasterization seam; local production-renderer captures do not show it. This known fixture artifact is not retouched, and CPU previews are not used as Windows promotional screenshots or GPU acceptance evidence.

## Recorder and named modes — September 8, 2026

The keyboard grid is replaced by an explicit Record/Stop flow and numbered key cards, with double-modifier/right-arrow presets and a collapsible manual fallback. The macOS editor keeps its Save/Cancel footer outside its scrolling content. The Windows manual layout shortens the sequence viewport so the footer stays inside the 800 × 656 panel at the minimum window size. No synthetic input was sent during layout review.

Modes have numbered color-coded cards, separate active/editing text, name/color controls, reorder arrows and a deletion confirmation. The macOS button guide is collapsible so the mode controls and actions get priority. The optional Mac indicator uses a black capsule below the usable screen's top edge; it is nonactivating/click-through rather than a notch overlay. A pure frame test covers positive and negative-origin screen coordinates. Its sample render is not a photograph of a real notch or a multi-display acceptance result.

Local minimum-size recorder, expanded manual, mode-card and name/color renders were inspected. Mac offscreen glass still leaves blank sidebar regions locally, so full-window README screenshots must come from inspected native CI outputs. Windows local renders here ran its production renderer on macOS; native Windows CPU fixtures are a separate required CI review. Neither certifies actual Windows input, GPU/Mica, screen-reader navigation, or Mac Spaces/menu-bar rendering.

Native Windows CPU fixtures from CI 34215691461 were inspected at both sizes: recorder controls, mode editing and both equal-height card rows fit. The expanded manual editor's footer is inside its panel. Follow-up changes make its sequence rows denser so two taps fit without partial clipping, update the reserved-gesture help to describe a multi-mode cycle, and retarget the sample scroll offsets to the taller mode section. The documented CPU gradient seam remains a fixture limitation, not a retouched image or a GPU acceptance pass.

### Interactive checks still required

On physical macOS and Windows installations:

- Navigate every page at default and minimum window sizes.
- Test keyboard focus, screen-reader labels and 100/150/200% display scaling.
- Confirm selectors, optional action fields, Test buttons and result messages remain usable.
- Check favorite/last-connected behavior, explicit linking and trust with two watches.
- Confirm cancellation, reconnects, sleep/wake, Bluetooth permissions and missing-adapter behavior.
- Check Mica on supported Windows 11 versions and the fallback on Windows 10.

No blanket visual/accessibility pass or real-device certification is claimed. Record evidence through the hardware issue template and update [Compatibility](docs/COMPATIBILITY.md) only after reproducible tests.
