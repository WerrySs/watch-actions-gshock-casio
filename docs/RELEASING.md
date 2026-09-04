# Releasing

The `Release` workflow can always build review artifacts through `workflow_dispatch`. It publishes a GitHub Release only for a pushed `v*` tag and only when platform signing and macOS notarization succeed.

## Required repository secrets

macOS:

- `APPLE_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12`.
- `APPLE_CERTIFICATE_PASSWORD`: password for that `.p12`.
- `APPLE_ID`: Apple ID used by the notary service.
- `APPLE_ID_PASSWORD`: app-specific password for that Apple ID.
- `APPLE_TEAM_ID`: Apple Developer Team ID.

Windows:

- `WINDOWS_CERTIFICATE_BASE64`: base64-encoded Authenticode `.pfx`.
- `WINDOWS_CERTIFICATE_PASSWORD`: password for that `.pfx`.

Secrets are imported only on ephemeral native runners and are never written to artifacts or logs. Fork pull requests cannot access the release workflow secrets.

## Prepare a version

1. Update the workspace version in `Cargo.toml` and the `Unreleased` section in `CHANGELOG.md`.
2. Run the full local validation documented in `CONTRIBUTING.md`.
3. Merge through a reviewed pull request with a green `CI` check.
4. Create and push a signed tag matching the workspace version:

```console
git tag -s v0.1.0 -m "WatchBridge 0.1.0"
git push origin v0.1.0
```

The workflow verifies the tag's version against Cargo metadata before packaging.

## Artifacts

- `WatchBridge-vVERSION-macOS-universal.dmg`
- `WatchBridge-vVERSION-macOS-universal.zip`
- `WatchBridge-vVERSION-macOS.sha256`
- `WatchBridge-vVERSION-Windows-x64.zip`
- `WatchBridge-vVERSION-Windows-x64.sha256`

The macOS build is universal (`arm64` + `x86_64`), hardened-runtime signed, notarized, and stapled. The Windows executable is Authenticode signed before it is archived. The publish job verifies every checksum again before creating the release.

Do not create a public release from a local machine or upload an unsigned replacement under an existing version.
