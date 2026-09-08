# Working on WatchBridge

Read [Contributing](CONTRIBUTING.md), [Security](SECURITY.md) and the relevant documentation before changing the project. Keep source, interface text, GitHub content and documentation in English. Preserve the native-client architecture and the documented experimental/hardware-validation limits.

## Change and release policy

For maintainer-requested changes, a completed delivery includes a **new downloadable GitHub release**, not just a commit, tag or temporary CI artifact. The maintainer has authorized this release step for completed change batches. This is not permission to change repository visibility, bypass checks or publish a stable build without its separate prerequisites.

1. Work on a focused branch, open a PR, inspect its diff and tests, and merge only after **Required checks** passes. Never push directly to protected `main`, force-push it or bypass protection.
2. Follow [Releasing](docs/RELEASING.md). Publish from the green merged source using the existing Release workflow; keep `main` unchanged while it builds. Use an experimental beta while signing or hardware acceptance remains incomplete.
3. Verify the new release is published with a descriptive title, accurate notes, both native applications and checksum files. Check the downloaded packages, not just the workflow conclusion.
4. Update the README's exact-version download links and feature availability through a checked PR. Documentation/release-link follow-ups that complete this same delivery do not require an endless sequence of identical binary releases. If application code changes again, build a new release.
5. Give the user the release URL and any outstanding limitations. If publishing fails, explain the blocker; never describe CI artifacts as a published release.

External contributors submit PRs; they do not need release credentials or publication access. Preserve least-privilege workflow tokens and signing gates. Do not replace existing release assets, move tags, grant broad token permissions or remove OS security warnings to complete a release.

## Local-data protection

Never commit or upload `.ai/`, `.workos/`, local app state, raw Bluetooth logs, credentials, signing material or private audit backups. Check the staged diff before every commit. Keep private project memory and any personal knowledge vault local; these instructions do not authorize uploading them.
