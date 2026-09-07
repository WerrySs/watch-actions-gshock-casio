# Design validation scope

## macOS

The committed images in `docs/screenshots/` are **offscreen section renders** using SwiftUI with sample data, not screenshots proving full-window interaction or a hardware connection. They exclude the system title bar and sidebar. Bluetooth and real saved-state access are disabled in snapshot mode.

The intended layout retains the reference's prominent watch image, cached status and two-column action grid. A neutral shared watch PNG replaces manufacturer imagery; both Dashboard and button guide use it. Action cards reserve common header/control/value/help regions.

Check regenerated snapshots for aligned cards, readable labels, the A/B/C/D guide, cached timestamps and supported model examples. Source screenshots supplied by the owner are not committed because they contain third-party product imagery.

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
