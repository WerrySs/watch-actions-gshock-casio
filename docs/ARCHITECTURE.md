# Architecture

WatchBridge uses native presentation on each platform and shares the code that benefits most from one implementation.

## Components

```text
Compatible watch
      │ Bluetooth LE
      ├──────────────► macOS: CoreBluetooth + SwiftUI/AppKit
      │                               │
      │                               ▼ C ABI
      └──────────────► Windows: btleplug + Slint ─────► Rust core
                                                        │
                                                        ├─ protocol codec
                                                        ├─ model validation
                                                        ├─ bounded persistence
                                                        └─ cached state/history
```

The macOS client stays in Swift because SwiftUI, AppKit visual-effect materials, CoreBluetooth, the menu bar, Shortcuts, and ServiceManagement provide a more coherent Mac experience than a cross-platform widget toolkit. It links the Rust core as a static library through the small `CWatchBridge` header.

The Windows client is Rust end to end. Slint renders the interface, `btleplug` handles Bluetooth LE, and Mica is requested through the native window handle. Unsupported Windows versions retain the opaque fallback styling.

## State model

`AppData` is the portable source of truth for:

- saved and manually registered watches;
- favorite selection and exact configured model;
- the latest snapshot read from each watch;
- pending changes to apply on the next connection;
- allowlisted computer actions; and
- bounded connection history.

Loaded data is normalized before use. The model caps collection sizes and text lengths, discards invalid identifiers, bounds numeric values, and prevents a manually registered or never-connected watch from becoming trusted.

The two platform clients currently keep separate local state because operating-system app data directories are intentionally local. The JSON schema is compatible for future explicit export/import without introducing cloud synchronization.

## Connection lifecycle

1. The client passively scans for the documented compatible service or manufacturer-prefixed device name.
2. The physical watch initiates a short session through one of its supported button gestures or scheduled connection windows.
3. WatchBridge identifies the physical device and safely associates a single matching manual record when possible.
4. The gesture is decoded before any optional computer action runs.
5. Actions run only if that physical device has previously connected and was explicitly trusted.
6. Current condition and, for `CNCT`, the full supported snapshot are read.
7. Bounded pending changes are written, with time sent last because the watch may disconnect after receiving it.
8. The session result and latest snapshot are persisted before returning to passive discovery.

## Security boundaries

- Bluetooth packet parsing rejects short or malformed frames.
- Requests and operating-system actions have deadlines.
- URLs are limited to HTTP and HTTPS with a host.
- There is no arbitrary command or script action.
- User photos are decoded and re-encoded before storage; original metadata and filenames are not retained.
- State files and images have explicit size limits and reject symbolic-link indirection.
- CI tokens default to read-only, third-party workflow actions are not used, and every referenced GitHub action is pinned to a full commit SHA.
