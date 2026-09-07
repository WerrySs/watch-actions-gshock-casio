# WatchBridge experimental beta

Download the **macOS-universal DMG/ZIP** for Apple silicon or Intel Macs, or the **Windows-x64 ZIP** for a Windows PC. SHA-256 checksum files accompany the archives.

This is an experimental review build, not a stable release. Physical-watch testing and interactive Windows acceptance are incomplete. macOS is ad-hoc signed, not Developer ID signed/notarized; Windows has no Authenticode signature when distribution secrets are absent. OS security warnings are expected. Do not disable Gatekeeper, SmartScreen or antivirus protections. Building from reviewed source is an alternative.

The code targets the supported GW-B5600/module-3461 variants only. Hardware validation on each OS is still required; CI compilation and startup smoke checks do not certify real-device behavior. Windows currently has read-only cached reminder/alarm/settings views and no photo import.

This preview adds per-device queues, fail-closed event decoding, protected-state recovery, explicit registration linking, bounded actions and packaging checks. Old unassigned changes are preserved but not sent; recreate them for the correct physical watch. Back up local state before testing.

Read [Installation](https://github.com/WerrySs/watch-actions-gshock-casio/blob/main/docs/INSTALLATION.md), [Compatibility](https://github.com/WerrySs/watch-actions-gshock-casio/blob/main/docs/COMPATIBILITY.md), [Contributing](https://github.com/WerrySs/watch-actions-gshock-casio/blob/main/CONTRIBUTING.md) and [Security](https://github.com/WerrySs/watch-actions-gshock-casio/blob/main/SECURITY.md). Packages include third-party license texts. WatchBridge is independent of Casio; CASIO and G-SHOCK identify hardware, not endorsement.

Windows reminders, alarms and settings are cached read-only views; photo import and editor parity are not implemented. Only the GW-B5600/module 3461 protocol target is admitted. No exact watch/OS combination is hardware-certified yet. Please report reproducible results using the hardware-validation issue template, without identifiers or personal watch content.
