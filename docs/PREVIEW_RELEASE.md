# WatchBridge private preview

Download the **macOS-universal DMG/ZIP** for Apple silicon or Intel Macs, or the **Windows-x64 ZIP** for a Windows PC. SHA-256 checksum files accompany the archives.

This is an experimental, private review build. macOS is ad-hoc signed, not Developer ID signed/notarized; Windows has no Authenticode signature when distribution secrets are absent. OS security warnings are expected. Do not disable Gatekeeper, SmartScreen or antivirus protections. Building from reviewed source is an alternative.

The code targets the supported GW-B5600/module-3461 variants only. Hardware validation on each OS is still required; CI compilation and startup smoke checks do not certify real-device behavior. Windows currently has read-only cached reminder/alarm/settings views and no photo import.

This preview adds per-device queues, fail-closed event decoding, protected-state recovery, explicit registration linking, bounded actions and packaging checks. Old unassigned changes are preserved but not sent; recreate them for the correct physical watch. Back up local state before testing.

See the repository's Installation, Compatibility, Contributing and Security guides. The source and downloads remain private to authorized collaborators. WatchBridge is independent of Casio; CASIO and G-SHOCK are hardware-identification references, not endorsements.
