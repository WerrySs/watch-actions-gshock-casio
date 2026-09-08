# Architecture

WatchBridge has two desktop clients and a shared Rust core, without a web server, browser runtime, account service or cloud synchronization.

| Component | Responsibility |
| --- | --- |
| `crates/core` | Packet codecs, supported-model validation, Rust state schema, persistence and C ABI |
| `apps/macos` | SwiftUI/AppKit, CoreBluetooth, Mac actions, local collection and editors |
| `crates/windows` | Rust/Slint, btleplug/WinRT Bluetooth, Windows actions and collection |
| `crates/xtask` | macOS static-library preparation and universal app packaging |

macOS uses native system materials, menus and controls. Windows uses compiled Slint controls with native Windows APIs and requests Mica where supported; it is **not WinUI**. An opaque fallback remains available. See the platform feature matrix in the [README](../README.md).

## Local state and migration

Windows stores Rust `AppData` schema 4 in `state.json`, migrating schema-2/3 actions and the original Alternate layer into named profiles. macOS reads legacy `config.json` and writes versioned `config-v2.json`, leaving the legacy file untouched; its pending queue remains `pending-by-watch-v2.json`. A failed newer-file load never falls back silently. These formats are **not interchangeable**. See [Installation](INSTALLATION.md); back up the full data folder before upgrading and do not alternate versions against it.

Both clients cache watch snapshots and bounded history. The dashboard favorite is a presentation choice, not permission to redirect a write. Prepared changes belong to a specific linked physical watch ID. Legacy global queues are retained but never executed; recreate them with an explicit target.

Failed state reads or saves pause subsequent writes and actions. Original files are not replaced with empty defaults after decode errors. Rust rejects newer schemas; the Swift pending-queue decoder rejects unknown versions and invalid entries. Cached measurements are last-known readings, not live data.

## Connection lifecycle

1. Discover an explicitly supported, manufacturer-prefixed Bluetooth name. A service UUID alone is insufficient.
2. Establish the expected GATT service and decode a recognized connection event.
3. Keep physical devices separate. Manual registrations are linked only through a user action, which resets trust.
4. Recheck physical-device trust after the handshake. A configured switch gesture changes that watch's session layer; otherwise run the layer's allowlisted action. Unknown/reserved protocol events do nothing. An in-flight action blocks overlapping launches and mode switches. AUTO always uses Normal.
5. Read condition; perform the extended refresh for CNCT.
6. On CNCT, apply only that device's queue. Remove a change only after acknowledged writes, and only if its value has not since changed.
7. Send time last. A dropped connection does not prove synchronization succeeded.
8. Persist the result and disconnect, retaining unconfirmed work. Windows accepts cancellation during a session; macOS fails pending requests on disconnection.

Names and local identifiers are **not cryptographic authentication**. OS Bluetooth security and explicit user authorization remain part of the trust boundary.

## Resource and security boundaries

- Mode IDs, names, colors, ordered profiles and actions are persisted (up to 100 named profiles). Active modes are bounded in-memory maps keyed by physical watch ID. Trust/relink changes clear the relevant mode; structure/switch changes, restart and reset return to Normal. Missing IDs never route edits into Normal.
- The shared Rust 81-key catalog and pure recorder accept bounded physical-key transitions. Swift calls the recorder via its ownership-safe C ABI; Windows uses it directly. Native local AppKit/winit adapters run only during explicit editor capture. Balanced Core Graphics/SendInput plans check focus/held keys before every step; no delay occurs while keys are held. Recorded payloads use an invalid legacy-key sentinel so older pickers cannot silently play a default arrow.
- Windows reuses Slint's existing winit backend via the `unstable-winit-030` feature, with Slint constrained to `~1.17.1` and the resolved version locked. No new recorder/input dependency is introduced. Review this adapter explicitly before a Slint minor upgrade.
- macOS's optional mode HUD uses a nonactivating, click-through AppKit panel positioned inside the primary screen's visible frame, below the menu bar. Observation updates it only when display state changes; no screen capture, keyboard monitoring or polling is involved.
- Requests, setup and helper processes have deadlines. A launched user application is intentionally not killed by a helper timeout.
- Mac GATT writes, including handshake replies, share a serialized acknowledgement path.
- State files are size-limited and atomically replaced. Direct file/parent symlink paths are rejected; this is not a defense against a compromised same-user process.
- Windows command delivery, histories, traces, watch collections and queues are bounded.
- Mac photos are decoded/re-encoded locally with generated filenames. No photo API or scraping is used.
- Workflow tokens are read-only except in the isolated publishing job. Actions use full-SHA pins; signing secrets never enter pull-request jobs.
