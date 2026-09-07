# Releasing WatchBridge

Repository: `WerrySs/watch-actions-gshock-casio`. Keep it **private** until the owner explicitly approves publication.

## CI downloads

Successful CI runs attach two review artifacts for 14 days:

- `WatchBridge-macOS-universal-review`: DMG, ZIP and SHA-256 file.
- `WatchBridge-Windows-x64-review`: portable ZIP and SHA-256 file.

Native runners execute tests, build and run a startup smoke check without Bluetooth or saved user data. macOS verifies arm64 and x86_64 slices; Windows links the MSVC runtime statically. Startup checks do not validate interactive UI or physical Bluetooth hardware.

## Private prerelease

After green CI, from main:

```console
gh workflow run release.yml --repo WerrySs/watch-actions-gshock-casio --ref main -f version=0.1.0 -F publish_preview=true
gh run list --repo WerrySs/watch-actions-gshock-casio --workflow release.yml
```

Release reruns tests and dependency policy, packages both clients, verifies checksums and creates `preview-vVERSION-RUN_NUMBER`. Assets are attached to a draft before it becomes downloadable. Preview publishing explicitly refuses a non-private repository. With the default `publish_preview=false`, it produces artifacts only.

Keep `main` unchanged until a publishing run finishes. The preview guard refuses to retarget already-built artifacts if `main` advances: start a fresh run instead. GitHub's automatic token cannot publish a historical target whose workflow files differ from the default branch; do not add a broad personal token to work around that restriction. See [GitHub's release permission requirements](https://docs.github.com/en/rest/releases/releases#create-a-release).

Previews may be **ad-hoc signed on macOS and unsigned on Windows**. Do not remove these warnings or instruct users to disable Gatekeeper, SmartScreen or antivirus. See [Installation](INSTALLATION.md).

## Signed distribution

Configure these Actions secrets before a stable release:

| Platform | Secrets |
| --- | --- |
| macOS signing | `APPLE_CERTIFICATE_BASE64` (Developer ID Application .p12), `APPLE_CERTIFICATE_PASSWORD` |
| Apple notarization | `APPLE_ID`, `APPLE_ID_PASSWORD` (app-specific), `APPLE_TEAM_ID` |
| Windows signing | `WINDOWS_CERTIFICATE_BASE64` (Authenticode .pfx), `WINDOWS_CERTIFICATE_PASSWORD` |

Certificates are imported only on ephemeral native runners. Never commit or attach signing files, passwords or tokens. Stable v* tags cannot publish unless Developer ID signing, notarization and Authenticode signing succeed.

1. Update Cargo.toml, Cargo.lock and [Changelog](../CHANGELOG.md).
2. Run [development checks](../CONTRIBUTING.md) and complete the [hardware matrix](COMPATIBILITY.md).
3. Review and merge with green CI. Repository visibility needs a separate owner decision.
4. Create a signed tag matching the workspace version:

```console
git tag -s v0.1.0 -m "WatchBridge 0.1.0"
git push origin v0.1.0
```

Do not upload unsigned replacements under a signed version or bypass a failed gate.

## Release files

```text
WatchBridge-vVERSION-macOS-universal.dmg
WatchBridge-vVERSION-macOS-universal.zip
WatchBridge-vVERSION-macOS.sha256
WatchBridge-vVERSION-Windows-x64.zip
WatchBridge-vVERSION-Windows-x64.sha256
```

Archives include licensing notices. Checksums detect corruption; they do not replace publisher signing. Keep failed partial releases as drafts, repair the cause and use a new preview number.

## Repository safeguards

Use read-only default tokens, full-SHA pins, no workflow bot approval of PRs, and dependency alerts. Private-repository branch protection and some secret-scanning/reporting features depend on the GitHub plan. If GitHub rejects those settings, document the limitation and preserve privacy; do not change visibility to enable them.
