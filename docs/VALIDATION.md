# Validation and remaining acceptance work

## Automated review

The 2026-09-07 local review exercised shared Rust tests, Rust linting (including the Windows target), Swift unit tests, workflow syntax checks, universal macOS packaging and startup. Regression coverage includes reserved connection reasons, per-watch queues, edits during in-flight writes, explicit linking without trust, invalid queue values, future schemas, corrupt-file preservation, symlink rejection and helper deadlines.

Native Windows execution is checked on the Windows CI runner, not inferred from cross-compilation. Consult the [CI history](https://github.com/WerrySs/watch-actions-gshock-casio/actions/workflows/ci.yml) for the exact commit and download artifacts. The [Release workflow](https://github.com/WerrySs/watch-actions-gshock-casio/actions/workflows/release.yml) independently gates downloads on tests, full-history secret scanning, dependency policy, packaging and checksums.

The September 8 action-layer/keyboard review adds legacy action decoding and schema migration, per-watch mode/trust isolation, switch reversibility, AUTO routing, invalid key/repeat rejection and balanced native modifier-release plans (including partial Windows insertion cleanup). Local checks passed 27 Rust-core tests and 20 Swift tests plus Windows MSVC-target linting. Native Windows tests run in CI. None of these tests sends input into a user's desktop or substitutes for physical BLE/permission/focus acceptance; see [Action layers](ACTION_LAYERS.md).

The subsequent recorder/multiple-mode change adds shared recording tests (including two distinct Command taps), migration of the old Alternate actions, named/color mode order, deletion/stale-ID handling, local-event adapters and indicator frame geometry. [CI 34215691461](https://github.com/WerrySs/watch-actions-gshock-casio/actions/runs/34215691461) passed every native/security job and Required checks at `104af5c`: 34 Rust-core tests on Unix (33 on Windows), 26 Swift tests and 14 native Windows-client tests. Both clients packaged and passed no-BLE startup checks; all three downloaded archive checksums and both ZIP integrity checks passed locally. The Rust Windows client also builds/lints locally on macOS, which is not Windows execution evidence. Recording and playback were not exercised against an uncontrolled desktop. Subsequent review refinements are validated separately in the PR checks.

macOS screenshots are sample-data offscreen renders. The [design validation scope](../design-qa.md) explicitly separates those from interactive testing.

## Dependency audit

The local RustSec scan on 2026-09-07 reported no known vulnerabilities and four indirect **unmaintained** notices: bincode 2.0.1, paste 1.0.15, rustybuzz 0.20.1 and ttf-parser 0.25.1. These upstream notices remain visible; they were not suppressed to claim a clean audit. Dependency policy also reports allowed duplicate transitive versions. Track upstream replacements before stable distribution. Audits are point-in-time evidence, not a guarantee of safety.

## Public experimental beta

The owner explicitly authorized opening the repository on September 7, 2026 with physical-watch and interactive acceptance tests and publisher signing still pending. [WatchBridge 0.1.0 Beta 3](https://github.com/WerrySs/watch-actions-gshock-casio/releases/tag/beta-v0.1.0-3) is a public experimental release, not a production-readiness or hardware-certification claim.

The [public-beta checklist](PUBLIC_BETA_CHECKLIST.md) covered Git history and Actions privacy review, green native [CI](https://github.com/WerrySs/watch-actions-gshock-casio/actions/runs/34116593291) and [release](https://github.com/WerrySs/watch-actions-gshock-casio/actions/runs/34116595065) runs on commit `db345172fe41e1d26c38cf1c5be32471d8d4a0f9`, and archive/checksum/licensing verification. After the authorized switch, main-branch protection, secret scanning, push protection, dependency alerts and private vulnerability reporting were enabled and verified.

Minimum physical tests on macOS and Windows remain pending in [the acceptance-tracking issue](https://github.com/WerrySs/watch-actions-gshock-casio/issues/2). Do not mark them complete from unit tests, CI runners, an offscreen screenshot, or user activity in the older Swift prototype. The beta warning and unverified compatibility matrix remain visible.

## Required before a stable release

- Obtain and configure Apple Developer ID/notarization and Windows Authenticode credentials. Current previews may be unsigned.
- Complete the exact-model/OS [hardware matrix](COMPATIBILITY.md), including two-watch isolation, reconnects, short TIME/FIND sessions and interrupted writes.
- Test interactive Windows layout/Mica, keyboard navigation, scaling and accessibility on a real desktop; test Mac title-bar/sidebar and permission flows.
- Validate native computer actions manually. Screen locking is reported as a request, not proof the screen is locked. On newer Macs it requires explicit Accessibility permission for the OS shortcut.
- Validate cycles of three or more named modes with two trusted watches, reorder/delete, restart/trust resets and AUTO staying Normal. Test the window-local recorder, double Command in a chosen utility, right-arrow twice, mixed chords, Escape/focus-loss cancellation and busy-action gating. Check permission/elevated-target rejection, held keys, non-US/AltGr layouts and focus changes between steps. Check the optional Mac indicator on notched/external displays, menu-bar color, Spaces and display scaling. Never use destructive shortcuts as fixtures.
- Resolve or document an accepted mitigation for the indirect unmaintained dependency notices.
- Obtain the owner's approval for stable distribution after the preceding gates are met. Release publication never changes repository visibility automatically.

## Primary implementation references

- [Apple keyboard shortcuts](https://support.apple.com/en-us/102650) documents Control-Command-Q for screen locking.
- [AXIsProcessTrusted](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted) checks existing Accessibility trust; the app does not grant it.
- Watch protocol scope and button procedures are listed in [References](REFERENCES.md).
