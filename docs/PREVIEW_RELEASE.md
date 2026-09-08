# WatchBridge experimental beta

Download the **macOS-universal DMG/ZIP** for Apple silicon or Intel Macs, or the **Windows-x64 ZIP** for a Windows PC. SHA-256 checksum files accompany the archives.

This is an experimental review build, not a stable release. Physical-watch testing and interactive Windows acceptance are incomplete. macOS is ad-hoc signed, not Developer ID signed/notarized; Windows has no Authenticode signature when distribution secrets are absent. OS security warnings are expected. Do not disable Gatekeeper, SmartScreen or antivirus protections. Building from reviewed source is an alternative.

The code targets the supported GW-B5600/module-3461 variants only. Hardware validation on each OS is still required; CI compilation and startup smoke checks do not certify real-device behavior. Windows currently has read-only cached reminder/alarm/settings views and no photo import.

## New in this beta

- **Record keyboard shortcuts** on both clients: Record/Stop, reviewed key sequences, modifier-only taps such as double Command, and presets including Right twice. Recording is local to the focused editor, with no global keyboard hook.
- **Create named, colored action modes** and reserve a supported watch gesture to cycle through them. Reorder, rename and recolor modes; the active mode stays isolated per trusted physical watch. AUTO always uses Normal.
- **Recognize the active mode on macOS** with a colored menu-bar watch symbol and an optional black, click-through indicator below the menu bar. It does not depend on notch geometry.
- **Cleaner native layouts:** aligned gesture cards, bounded Windows controls, a settings target banner that reserves its own space, and a Dashboard glow that fades within its bounds.

Keyboard playback still needs real-target acceptance, including double Command in your chosen utility. Synthetic input may be rejected by the OS or target application. macOS playback requires user-granted Accessibility permission; Windows playback is not elevated. These changes do not expand the supported watch family or claim live Bluetooth connectivity.

## Before upgrading

Back up the complete local app-data folder. Existing Normal/Alternate actions and keyboard settings migrate. Windows now saves schema **4**; older clients refuse that newer state. macOS writes **config-v2.json**, preserving the legacy **config.json**; older apps will not see subsequent configuration edits. Do not alternate versions against the same data folder or copy state between platforms. See [Action modes, recording and rollback](https://github.com/WerrySs/watch-actions-gshock-casio/blob/main/docs/ACTION_LAYERS.md).

Per-device queues, fail-closed event decoding, protected-state recovery, explicit registration linking and bounded actions remain in place. Old unassigned changes are preserved but not sent; recreate them for the correct physical watch.

Read [Installation](https://github.com/WerrySs/watch-actions-gshock-casio/blob/main/docs/INSTALLATION.md), [Compatibility](https://github.com/WerrySs/watch-actions-gshock-casio/blob/main/docs/COMPATIBILITY.md), [Contributing](https://github.com/WerrySs/watch-actions-gshock-casio/blob/main/CONTRIBUTING.md) and [Security](https://github.com/WerrySs/watch-actions-gshock-casio/blob/main/SECURITY.md). Packages include third-party license texts. WatchBridge is independent of Casio; CASIO and G-SHOCK identify hardware, not endorsement.

Please report reproducible results using the hardware-validation issue template, without identifiers or personal watch content.
