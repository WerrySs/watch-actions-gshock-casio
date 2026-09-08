# Releasing WatchBridge

Repository: `WerrySs/watch-actions-gshock-casio`. Repository visibility and release publication are separate decisions. The owner must explicitly authorize opening the source after the [public-beta checklist](PUBLIC_BETA_CHECKLIST.md); no workflow changes visibility automatically.

## Completion policy

The maintainer's standing instruction is to publish a downloadable release for every completed batch of requested changes. A merged PR, a tag without apps, or a successful CI artifact is not the release deliverable. Use the existing gated workflow; this policy does not automatically publish every intermediate commit or untrusted contributor PR.

1. Update the changelog and beta notes for the completed changes. Use a feature branch, a PR and green **Required checks**; wait for green CI on the merged source too.
2. Dispatch Release from that `main` commit and keep `main` unchanged until publication finishes. Publish an experimental beta unless the separate stable-release prerequisites are met.
3. Confirm the tag targets the built commit, the release is no longer a draft, and its title, notes and prerelease status describe the build accurately.
4. Download the macOS DMG/ZIP, Windows ZIP and both checksum files from the public release links. Verify SHA-256 and archive integrity; retain native-runner test/smoke evidence. A download or startup check is not physical-watch acceptance.
5. Update the README's exact-version links, feature availability and release evidence through a green PR, then provide the release URL to the requester. These documentation-only follow-ups belong to the same delivery and do not recursively require another identical binary release. Further app changes do require new packages and a new release.

If a build, permission or publishing gate fails, report it explicitly and fix the cause. Never substitute a temporary CI link while claiming publication, overwrite old assets, move an existing tag, or bypass signing/security gates. The September 8, 2026 standing authorization covers experimental releases of completed requested work; it does not authorize changing visibility or certifying a stable release.

## CI downloads

Successful CI runs attach two review artifacts for 14 days:

- `WatchBridge-macOS-universal-review`: DMG, ZIP and SHA-256 file.
- `WatchBridge-Windows-x64-review`: portable ZIP and SHA-256 file.

Native runners execute tests, build and run a startup smoke check without Bluetooth or saved user data. macOS verifies arm64 and x86_64 slices; Windows links the MSVC runtime statically. Startup checks do not validate interactive UI or physical Bluetooth hardware.

## Experimental beta

After green CI, from main, use the default for a private repository:

```console
gh workflow run release.yml --repo WerrySs/watch-actions-gshock-casio --ref main -f version=0.1.0 -F publish_preview=true
gh run list --repo WerrySs/watch-actions-gshock-casio --workflow release.yml
```

For a repository that the owner has already made public, explicitly opt in to public beta downloads:

```console
gh workflow run release.yml --repo WerrySs/watch-actions-gshock-casio --ref main -f version=0.1.0 -F publish_preview=true -F allow_public_preview=true
```

Release reruns tests and dependency policy, packages both clients, verifies checksums and creates `beta-vVERSION-RUN_NUMBER`. Assets are attached to a draft before it becomes downloadable. A public repository requires `allow_public_preview=true`; its default is false. With `publish_preview=false`, manual runs produce artifacts only. Neither option bypasses stable-release signing or certifies physical hardware.

Beta titles use **WatchBridge VERSION Beta RUN_NUMBER · macOS & Windows**; signed stable releases use **WatchBridge VERSION · macOS & Windows**. Keep betas marked as prereleases. GitHub [does not allow a prerelease to be marked Latest](https://docs.github.com/en/rest/releases/releases#update-a-release), so do not promote an experimental build just to change the repository sidebar. After verifying a new beta's public downloads, update the README's release, package and checksum links in a reviewed PR. Retain the exact version in those links so a reader gets the documented build.

Keep `main` unchanged until a publishing run finishes. The preview guard refuses to retarget already-built artifacts if `main` advances: start a fresh run instead. GitHub's automatic token cannot publish a historical target whose workflow files differ from the default branch; do not add a broad personal token to work around that restriction. See [GitHub's release permission requirements](https://docs.github.com/en/rest/releases/releases#create-a-release).

Betas may be **ad-hoc signed on macOS and unsigned on Windows**. Do not remove these warnings or instruct users to disable Gatekeeper, SmartScreen or antivirus. Retain older internal-only previews as drafts when opening the repository. See [Installation](INSTALLATION.md).

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

Use read-only default tokens, full-SHA pins, no workflow bot approval of PRs, and approval for external contributors' workflows. Protect main with pull requests, strict **Required checks**, resolved conversations, no force pushes or deletions, and administrator enforcement. A sole maintainer cannot independently approve their own PR; do not claim a second-person review until another maintainer is available.

CI invokes dependency/license checks for every PR and exposes one aggregate result, so path filters cannot leave the required status indefinitely pending. Gitleaks scans full Git history using a checksum-pinned binary and redacted output. Raw scanner findings and private audit backups must not be uploaded.

Private-repository branch protection and some secret-scanning/reporting features depend on the GitHub plan. If GitHub rejects those settings, document the limitation; changing visibility still requires the owner's separate approval. Verify all protections, secret scanning/push protection, dependency alerts and private vulnerability reporting immediately after an authorized switch. See the [public-beta checklist](PUBLIC_BETA_CHECKLIST.md).

The owner authorized public experimental distribution on September 7, 2026. The repository is now public; physical-watch acceptance, interactive UI validation and publisher signing remain separate outstanding work. See [Validation](VALIDATION.md).
