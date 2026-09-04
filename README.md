# WatchBridge

WatchBridge is an independent desktop bridge for compatible Bluetooth watch buttons on macOS and Windows. It keeps watch data local, remembers the most recent synchronized state, and can map supported watch gestures to a small set of safe computer actions.

> [!IMPORTANT]
> WatchBridge is an unofficial community project. It is not affiliated with, authorized by, sponsored by, endorsed by, or supported by Casio Computer Co., Ltd. CASIO and G-SHOCK are trademarks of their respective owner and are referenced only to describe device compatibility.

![WatchBridge dashboard on macOS](docs/screenshots/dashboard.png)

## What it does

- Presents a native, translucent SwiftUI experience on macOS and a native Mica-style Slint experience on Windows.
- Lets you register any watch model before owning or pairing the physical watch.
- Uses a favorite watch on the Dashboard, falling back to the most recently connected watch.
- Keeps battery, temperature, home city, timer, alarms, reminders, settings, and connection history visible while disconnected.
- Lets macOS users supply their own watch photo. WatchBridge bounds, decodes, and re-encodes it as a metadata-free PNG stored only on that Mac.
- Maps supported `CNCT`, `TIME`, `FIND`, and automatic connection events to allowlisted computer actions.
- Blocks automatic actions until the exact physical watch has connected and the user explicitly trusts it.
- Queues watch changes and applies them on the next compatible connection.

The currently implemented Bluetooth protocol targets the compatible GW-B5600 family. Other models can be catalogued, but they should not be assumed to support synchronization until their protocol has been tested and documented.

## Native clients, shared core

| Layer | Technology | Responsibility |
| --- | --- | --- |
| Shared core | Rust | Validated data model, protocol codec, bounded persistence, history, and FFI |
| macOS client | Swift + SwiftUI/AppKit | Native materials, CoreBluetooth, local images, menu bar, and macOS actions |
| Windows client | Rust + Slint | Mica presentation, Windows BLE runtime, local state, and Windows actions |

This keeps the polished native macOS interface while sharing the security-sensitive protocol and validation logic with Windows. See [Architecture](docs/ARCHITECTURE.md) for boundaries and data flow.

## Interface

<p align="center">
  <img src="docs/screenshots/actions.png" alt="Aligned action cards and physical button guide" width="48%">
  <img src="docs/screenshots/my-watches.png" alt="Local watch collection" width="48%">
</p>

The action cards use a fixed grid and equalized internal regions, so controls remain aligned even when one action needs an extra value. Both clients keep their primary content inside a bounded, scrollable application window.

## Build locally

Requirements:

- Rust `1.98.1` through rustup.
- macOS 14 or later with Swift 6.2 to build the macOS client.
- Windows 10 or later to build and run the Windows client.

macOS:

```console
cargo xtask prepare-macos
swift run --package-path apps/macos WatchBridge
```

Windows:

```console
cargo run --package watchbridge-windows
```

Run the core checks:

```console
cargo fmt --all -- --check
cargo test --locked --package watchbridge-core
cargo clippy --workspace --all-targets -- -D warnings
```

The repository intentionally contains only the application source and small first-party assets. Build output, signing material, local app state, `.ai/`, and `.workos/` are ignored.

## Releases

GitHub Actions builds both clients on their native hosted runners. Manual workflow runs upload short-lived test artifacts. A `v*` tag can publish a GitHub Release only after the configured signing checks pass. See [Releasing](docs/RELEASING.md) for the exact secrets, validation steps, and artifact names.

No release artifact is committed to Git. Every downloadable archive has a SHA-256 checksum.

## Privacy and security

WatchBridge has no account, analytics, advertising SDK, or network upload service. It discovers compatible devices through the operating system Bluetooth API and stores app state locally. Read [Privacy](PRIVACY.md) and [Security](SECURITY.md) before testing a new device.

Computer actions are intentionally allowlisted. The project does not accept or execute arbitrary shell commands, and untrusted or manually registered records cannot trigger actions.

## Contributing

The repository is private during early hardware validation, but it is structured for public collaboration later. Read [Contributing](CONTRIBUTING.md), the [Code of Conduct](CODE_OF_CONDUCT.md), and [Support](SUPPORT.md) before opening a change.

## Responsible use and license

This software is intended for lawful, responsible, personal experimentation with hardware you control. You are responsible for device compatibility, local regulations, backups, and any action you configure.

The source code is available under the [MIT License](LICENSE). The MIT terms govern redistribution and modification; the personal-use statement describes the project's intended use and is not an additional license restriction.
