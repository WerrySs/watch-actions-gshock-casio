# Changelog

All notable changes are documented here. This project follows Semantic Versioning once releases begin.

## [Unreleased]

### Added

- Native translucent macOS client built with SwiftUI and AppKit.
- Native Windows client built with Rust, Slint, and Windows Mica.
- Shared Rust protocol, validation, history, and bounded persistence core.
- Offline watch collection, exact model selection, favorite/last-connected Dashboard behavior, and pre-pair registration.
- Local cached watch state and connection history.
- Metadata-free user watch images on macOS.
- Equalized action-card grid and physical-button guide.
- Least-privilege CI, scheduled dependency audits, signed release packaging, and SHA-256 checksums.

### Fixed

- Bind pending changes to physical watch IDs, preserve edits made while an older value is in flight, and quarantine legacy global queues.
- Reject unknown Bluetooth reasons instead of treating them as TIME gestures.
- Protect unreadable/newer local state from default-state overwrites; pause writes after save failures.
- Restrict discovery to the implemented GW-B5600 family; require explicit manual-to-physical linking without inherited trust.
- Keep launched Windows apps running, use the native lock request, and refresh action results in the interface.
- Serialize Mac handshake/write acknowledgements; do not report dropped time writes as successful synchronization.
- Bound connection setup, Windows session cancellation and command delivery.
- Align Windows action-card rows and preserve minimum window bounds.

### Distribution

- Rename the private repository to `WerrySs/watch-actions-gshock-casio`; retain the independent WatchBridge app name.
- Attach universal macOS and Windows x64 downloads to CI; support labeled experimental beta releases with an explicit opt-in for public preview publishing.
- Scan complete Git history with a checksum-pinned Gitleaks binary and redact scanner output; aggregate native and dependency jobs in one required CI check for every PR.
- Separate public-beta preparation from stable-release requirements and document physical-test limitations.
- Open the repository as an explicitly authorized experimental beta, protect main with required PR checks, and add named macOS/Windows releases with direct download links.
- Add installation, compatibility evidence, primary references and contribution guidance.
- Stable distribution still requires publisher certificates and real-device validation; previews are not hardware certification.

[Unreleased]: https://github.com/WerrySs/watch-actions-gshock-casio/commits/main
