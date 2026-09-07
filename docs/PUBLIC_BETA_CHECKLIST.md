# Public-beta maintainer checklist

Opening source code is separate from shipping a stable application. Never turn an untested case into a pass just to complete this list. The owner must authorize the visibility change; CI/release workflows do not change repository visibility.

## Before changing visibility

- Back up the repository and its current GitHub settings locally. Do not upload the backup.
- Scan all Git branches/tags and the current tree for secrets, private files and accidentally committed user data. Review commit metadata and embedded image metadata.
- Review existing Actions logs/artifacts, release attachments, issues and PRs. These may become public along with the repository. Archive findings locally with secrets redacted; do not publish raw audit output.
- Inspect documentation screenshots for personal data and confirm asset provenance and redistribution permissions. Do not add AI-created promotional images or manufacturer photography.
- Run the complete **Required checks** CI job on the exact release commit. Download both platform archives and verify their checksums and included licensing files.
- Keep the experimental warning, narrow device scope, platform feature matrix, unsigned-package notice and unverified hardware matrix prominent.
- Adapt the release workflow to permit a deliberate public beta without weakening the stable signing gate. Retain previous internal-only previews as drafts when appropriate.
- Complete the minimum physical tests below, or obtain an explicit owner decision to publish experimental source/downloads with these tests still outstanding. Document the remaining tests; never claim certification.

## Minimum physical tests — separate results for macOS and Windows

Record exact watch model/module, OS/build/architecture, app commit and test date in a hardware-validation issue. Do not publish Bluetooth identifiers, serial numbers, personal reminder contents or desktop notifications.

1. Start with computer actions blocked. Connect the supported physical watch using CNCT; verify it is recognized but no action executes before trust.
2. Explicitly link a saved registration, verify trust stays off, then authorize only a reviewed harmless action. Test FIND and TIME separately; do not use screen locking as the first action.
3. Disconnect, restart the app and verify cached readings/history remain available. Reconnect and check timestamps and session results.
4. Verify Bluetooth permissions, cancellation, sleep/wake and missing-adapter behavior without bypassing OS protections.
5. On a test watch you control, back up settings before a harmless queued change. Verify readback where supported and interrupted-write handling. Restore the original value.
6. Before stable release, use two physical watches to verify that favorite/model changes never redirect writes or transfer action trust.

CI startup smoke tests have Bluetooth, saved user state and automatic physical-watch actions disabled. They do not satisfy this list.

## Immediately after an authorized visibility change

- Protect `main`: pull requests, strict **Required checks** from GitHub Actions, resolved conversations, no force pushes/deletions, and administrator enforcement.
- A sole maintainer cannot independently approve their own PR. Keep PRs/checks required without claiming independent review; require a second reviewer once another maintainer is available.
- Enable and verify Dependabot alerts, secret scanning, push protection and private vulnerability reporting. Do not assume the visibility switch configured them correctly.
- Keep read-only default workflow permissions, GitHub-owned Actions pinned to full SHAs, no workflow bot approvals and approval for outside contributors' workflows.
- Verify the public README and download links without signing in. Do not copy authenticated screenshots that include private activity or unrelated notifications.

## Stable release is a separate gate

Stable tags require Apple Developer ID/notarization and Windows Authenticode signing. Real-device, interactive UI, accessibility, two-watch isolation, and dependency-maintenance acceptance remain required. See [Validation](VALIDATION.md) and [Releasing](RELEASING.md).
