# Validation and remaining acceptance work

## Automated review

The 2026-09-07 local review exercised shared Rust tests, Rust linting (including the Windows target), Swift unit tests, workflow syntax checks, universal macOS packaging and startup. Regression coverage includes reserved connection reasons, per-watch queues, edits during in-flight writes, explicit linking without trust, invalid queue values, future schemas, corrupt-file preservation, symlink rejection and helper deadlines.

Native Windows execution is checked on the Windows CI runner, not inferred from cross-compilation. Consult the [CI history](https://github.com/WerrySs/watch-actions-gshock-casio/actions/workflows/ci.yml) for the exact commit and download artifacts. The [Release workflow](https://github.com/WerrySs/watch-actions-gshock-casio/actions/workflows/release.yml) independently gates downloads on tests, full-history secret scanning, dependency policy, packaging and checksums.

macOS screenshots are sample-data offscreen renders. The [design validation scope](../design-qa.md) explicitly separates those from interactive testing.

## Dependency audit

The local RustSec scan on 2026-09-07 reported no known vulnerabilities and four indirect **unmaintained** notices: bincode 2.0.1, paste 1.0.15, rustybuzz 0.20.1 and ttf-parser 0.25.1. These upstream notices remain visible; they were not suppressed to claim a clean audit. Dependency policy also reports allowed duplicate transitive versions. Track upstream replacements before stable distribution. Audits are point-in-time evidence, not a guarantee of safety.

## Before opening an experimental beta

Complete the [public-beta checklist](PUBLIC_BETA_CHECKLIST.md), including privacy review of Git history and Actions, a fresh green native CI/release, owner authorization, and verification of repository protections. Public source availability is not a claim of production readiness.

Minimum physical tests on macOS and Windows remain pending. Do not mark them complete from unit tests, CI runners, an offscreen screenshot, or user activity in the older Swift prototype. If the owner chooses to open the source before these tests, that exception must be explicit and the beta warning and unverified compatibility matrix must remain visible.

## Required before a stable release

- Obtain and configure Apple Developer ID/notarization and Windows Authenticode credentials. Current previews may be unsigned.
- Complete the exact-model/OS [hardware matrix](COMPATIBILITY.md), including two-watch isolation, reconnects, short TIME/FIND sessions and interrupted writes.
- Test interactive Windows layout/Mica, keyboard navigation, scaling and accessibility on a real desktop; test Mac title-bar/sidebar and permission flows.
- Validate native computer actions manually. Screen locking is reported as a request, not proof the screen is locked. On newer Macs it requires explicit Accessibility permission for the OS shortcut.
- Resolve or document an accepted mitigation for the indirect unmaintained dependency notices.
- Obtain the owner's explicit approval before changing visibility. Release publication never changes it automatically.

## Primary implementation references

- [Apple keyboard shortcuts](https://support.apple.com/en-us/102650) documents Control-Command-Q for screen locking.
- [AXIsProcessTrusted](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted) checks existing Accessibility trust; the app does not grant it.
- Watch protocol scope and button procedures are listed in [References](REFERENCES.md).
