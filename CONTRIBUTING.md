# Contributing

Thank you for helping improve WatchBridge. The repository is private during early hardware validation, but the same review rules apply before it is opened more broadly.

## Ground rules

- Keep all source, interface text, issues, and documentation in English.
- Preserve the native-client architecture: SwiftUI/AppKit on macOS, Rust/Slint on Windows, and Rust for shared validation and protocol logic.
- Do not add manufacturer photography, scraped product assets, analytics, cloud storage, or undocumented telemetry.
- Do not add arbitrary command execution. New computer actions need a narrow allowlist, bounded input, a timeout, and explicit trust checks.
- Never commit `.ai/`, `.workos/`, local state, logs, signing material, credentials, or generated release artifacts.
- Document protocol claims with reproducible evidence that does not expose personal device identifiers.

## Development checks

From the repository root:

```console
cargo fmt --all -- --check
cargo test --locked --package watchbridge-core
cargo clippy --workspace --all-targets -- -D warnings
```

On macOS:

```console
cargo xtask prepare-macos
swift test --package-path apps/macos
swift build --package-path apps/macos
```

On Windows:

```console
cargo test --locked --package watchbridge-core
cargo test --locked --package watchbridge-windows
cargo clippy --locked --package watchbridge-windows --all-targets -- -D warnings
cargo build --locked --release --package watchbridge-windows
```

## Pull requests

Keep changes focused and explain the user-visible outcome, tests, privacy implications, and hardware validation performed. Add or update tests for parser, persistence, trust, and protocol changes. Include screenshots for interface changes at the default size and at the minimum usable size.

By contributing, you agree that your contribution is licensed under the repository's MIT License and that you will follow the Code of Conduct.
