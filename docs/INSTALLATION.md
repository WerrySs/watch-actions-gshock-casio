# Installation and review builds

## Download

Choose the newest experimental beta under [Releases](https://github.com/WerrySs/watch-actions-gshock-casio/releases). Public release assets can be downloaded without signing in; CI artifact downloads require a GitHub account. Access is limited to collaborators for any version retained as a draft or while the repository is private. CI artifacts are available for 14 days; release assets remain attached to their version.

- macOS 14+: universal DMG/ZIP contains an app with Apple silicon and Intel slices. Copy the app to Applications.
- Windows x64: extract the ZIP before starting WatchBridge.exe. Keep the included license and notices. The MSVC runtime is statically linked; normal Windows system components and graphics/Bluetooth drivers are still required.

Preview builds are not equivalent to a signed stable distribution. macOS ad-hoc signing verifies bundle integrity but not a trusted publisher; Windows previews may be unsigned. If your OS blocks an app, do not disable its security protections. Review the source or wait for signed distribution. Stable releases require Apple Developer ID/notarization and Windows Authenticode signing.

## Verify integrity

Put a package and its matching .sha256 file in the same folder. On macOS:

```console
shasum -a 256 -c WatchBridge-v0.1.0-macOS.sha256
```

The macOS checksum list contains both DMG and ZIP; download both to validate the entire list, or compare only the entry for your chosen file. On Windows PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 .\WatchBridge-v0.1.0-Windows-x64.zip
Get-Content .\WatchBridge-v0.1.0-Windows-x64.sha256
```

The digest must match exactly. A checksum detects corruption; it is not a publisher signature or proof of safety.

## First use

1. Read the compatibility guide. Enable Bluetooth and allow the app's OS Bluetooth permission where requested.
2. Ensure no other app is connected to the watch, then initiate CNCT from the supported physical watch.
3. In My Watches, explicitly link any pre-registration to the correct physical unit. Linking keeps computer actions blocked.
4. Review an action before testing it. Authorize the physical watch only when you want it to control this computer.
5. Use one watch for initial hardware testing. Readings shown after disconnect are cached, with their previous connection time.

On newer macOS versions, the screen-lock action needs Accessibility permission for WatchBridge to request the system Control-Command-Q shortcut. Without it the action reports that permission is missing; it never changes permissions or substitutes display sleep. Music/other app control may require the OS Automation permission. These optional permissions are not needed to browse saved readings. Validate actions manually before authorizing a watch.

## Upgrading and recovering local data

Quit WatchBridge before making a backup. macOS uses `~/Library/Application Support/WatchBridge/`; Windows uses `%LOCALAPPDATA%\WerrySs\WatchBridge\data\` (resolved through the OS known-folder API). Never post unredacted paths or logs in an issue.

The formats differ between platforms: there is no direct state-file interchange. Development Windows schema 4 adds named modes and recordings while migrating schema-2/3 settings; older builds refuse newer state. macOS writes `config-v2.json` after reading legacy `config.json` and leaves that legacy file untouched. Older macOS builds see only the legacy configuration, not new edits. Queues remain in `pending-by-watch-v2.json`; old unassigned entries are never automatically sent. Back up the complete data folder before upgrading and do not alternate versions against it. See [Modes, recording and rollback](ACTION_LAYERS.md).

If loading fails, originals are preserved and writes/actions are paused. Quit, copy the entire data directory somewhere safe, restore a valid backup and restart. Do not replace a newer-version file with defaults or delete it just to suppress an error. A future schema requires a compatible application version.
