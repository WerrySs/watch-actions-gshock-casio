# Contributing

Thank you for helping improve WatchBridge. This is an experimental community project: hardware validation, reproducible bug reports, documentation, and focused code changes are welcome. Opening the source does not certify the apps or any watch/OS combination.

## Ground rules

- Keep all source, interface text, issues, and documentation in English.
- Preserve the native-client architecture: SwiftUI/AppKit on macOS, Rust/Slint on Windows, and Rust for shared validation and protocol logic.
- Do not add manufacturer photography, scraped product assets, analytics, cloud storage, or undocumented telemetry.
- Do not add arbitrary command execution. New actions need a narrow allowlist, bounded input, helper-process deadlines, and explicit trust checks. Never kill an application the user requested to open merely because a helper deadline elapsed.
- Never commit `.ai/`, `.workos/`, local state, logs, signing material, credentials, or generated release artifacts.
- Document protocol claims with reproducible evidence that does not expose personal device identifiers.

## Development checks

From the repository root:

```console
cargo fmt --all -- --check
cargo test --locked --package watchbridge-core
cargo clippy --locked --workspace --all-targets -- -D warnings
```

On macOS:

```console
cargo xtask prepare-macos
swift test --package-path apps/macos
swift build --package-path apps/macos
WATCHBRIDGE_UNIVERSAL=1 cargo xtask package-macos
dist/macos/WatchBridge.app/Contents/MacOS/WatchBridge --smoke-test
```

On Windows:

```console
cargo test --locked --package watchbridge-core
cargo test --locked --package watchbridge-windows
cargo clippy --locked --package watchbridge-windows --all-targets -- -D warnings
cargo build --locked --release --package watchbridge-windows
target/release/watchbridge-windows.exe --smoke-test
```

## Pull requests

When changing dependencies, regenerate the bundled notices before committing:

```console
cargo install cargo-about --version 0.9.2 --features cli --locked
cargo about generate --workspace --locked --fail .github/licenses.hbs --output-file THIRD_PARTY_LICENSES.txt
```

Review generated license changes. Slint's custom text is hash-checked in `about.toml` and explicitly included by the template to cover cargo-about 0.9.2's LicenseRef output omission. Investigate upstream changes before updating those hashes/text. Never commit raw cargo-about JSON: it contains local paths.

Keep changes focused and explain the user-visible outcome, tests, privacy implications, and hardware validation performed. Add or update tests for parser, persistence, trust, and protocol changes. Include screenshots for interface changes at the default size and at the minimum usable size.

Use a feature branch or fork and open a pull request against `main`. The **Required checks** CI job must pass: it includes repository/history scanning, shared tests, dependency policy, and native macOS/Windows tests and packaging. Dependency checks run for documentation-only PRs too. External contributors' workflows may need maintainer approval before running. Do not paste raw Bluetooth logs: they can contain personal reminders and device identifiers. CI artifacts expire after 14 days; link the run as build evidence. Use the hardware validation issue template for real-device results, including the exact model/module, OS/build version, tested gestures and failed cases. A successful compiler run does not qualify a watch as hardware verified.

Before adding a device to [Compatibility](docs/COMPATIBILITY.md), establish that its buttons initiate computer-observable Bluetooth events. Sharing a brand, case design or service UUID is not sufficient. Add primary [references](docs/REFERENCES.md), sanitized regression fixtures and separate macOS/Windows evidence. See the [roadmap](docs/ROADMAP.md) for bounded feature ideas.

By contributing, you agree that your contribution is licensed under the repository's MIT License and that you will follow the Code of Conduct.
