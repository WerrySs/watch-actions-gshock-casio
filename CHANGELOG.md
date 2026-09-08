# Changelog

All notable changes are documented here. This project follows Semantic Versioning once releases begin.

## [Unreleased]

### Added

- Normal/Alternate action layers, switched by a reserved FIND/TIME/CNCT gesture, with per-physical-watch session modes and an explicit reset.
- Visual keyboard editors on both clients, using one shared key catalog, optional modifiers and 1–10 complete chord repetitions.
- Native keyboard emission with Accessibility checks on macOS and non-elevated SendInput on Windows, foreground/held-key guards and a three-second manual-test delay.
- Regression tests for old action settings, layer isolation/trust/AUTO behavior, bounded keyboard requests and native key-release plans.
- Native translucent macOS client built with SwiftUI and AppKit.
- Native Windows client built with Rust, Slint, and Windows Mica.
- Shared Rust protocol, validation, history, and bounded persistence core.
- Offline watch collection, exact model selection, favorite/last-connected Dashboard behavior, and pre-pair registration.
- Local cached watch state and connection history.
- Metadata-free user watch images on macOS.
- Equalized action-card grid and physical-button guide.
- Least-privilege CI, scheduled dependency audits, signed release packaging, and SHA-256 checksums.

### Fixed

- Place macOS target/protection banners inside the detail layout, above page content, instead of over navigation and headings.
- Fade the Dashboard watch halo to transparent inside its bounds, removing clipped glow edges and the oversized blur.
- Keep Dashboard, button sheets and action editors consistent about the active versus edited layer; identify AUTO as Normal-only.
- Initialize Windows keyboard rows once instead of rebuilding the key grid on state refresh.
- Give the conditional Windows main layout explicit bounds, equal-width gesture cards and bounded Test buttons; keep key labels and keyboard-editor buttons inside the panel.
- Bind pending changes to physical watch IDs, preserve edits made while an older value is in flight, and quarantine legacy global queues.
- Reject unknown Bluetooth reasons instead of treating them as TIME gestures.
- Protect unreadable/newer local state from default-state overwrites; pause writes after save failures.
- Restrict discovery to the implemented GW-B5600 family; require explicit manual-to-physical linking without inherited trust.
- Keep launched Windows apps running, use the native lock request, and refresh action results in the interface.
- Serialize Mac handshake/write acknowledgements; do not report dropped time writes as successful synchronization.
- Bound connection setup, Windows session cancellation and command delivery.
- Align Windows action-card rows and preserve minimum window bounds.

### Distribution

- Preserve legacy action settings on upgrade; Windows schema 3 prevents older builds from overwriting layer data. Keyboard/layer changes are in CI review builds, not the existing Beta 3 packages.
- Include keyboard, layer and settings-banner sample-data previews in PR CI artifacts for visual review.
- Render Windows client-area fixtures at default/minimum sizes without BLE or action callbacks, reject blank output, and refresh the inspected macOS README images.
- Use an optional CPU-rendered fixture build for hosted Windows visual checks, with captured process diagnostics and dependency-policy coverage; downloadable apps retain their production renderer.
- Rename the private repository to `WerrySs/watch-actions-gshock-casio`; retain the independent WatchBridge app name.
- Attach universal macOS and Windows x64 downloads to CI; support labeled experimental beta releases with an explicit opt-in for public preview publishing.
- Scan complete Git history with a checksum-pinned Gitleaks binary and redact scanner output; aggregate native and dependency jobs in one required CI check for every PR.
- Separate public-beta preparation from stable-release requirements and document physical-test limitations.
- Open the repository as an explicitly authorized experimental beta, protect main with required PR checks, and add named macOS/Windows releases with direct download links.
- Add installation, compatibility evidence, primary references and contribution guidance.
- Stable distribution still requires publisher certificates and real-device validation; previews are not hardware certification.

[Unreleased]: https://github.com/WerrySs/watch-actions-gshock-casio/commits/main
