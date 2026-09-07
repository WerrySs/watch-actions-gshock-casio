# Roadmap

Proposals, not shipped features or delivery commitments. Reliability and consent come before more models.

## Next useful additions

- Per-watch action profiles and a global pause control.
- An optional connection-only/read-only mode with clear indicators.
- Focus-session presets using a chosen macOS Shortcut or a narrowly scoped Windows integration.
- Meeting controls with explicit app targets; speaker mute must never be described as microphone mute.
- Preview selected calendar events before mapping them to the watch's five short reminder slots.
- Alarm/countdown presets, with a before/after diff and readback where the protocol permits it.
- Versioned local backup/import rather than copying incompatible platform state files.

No arbitrary shell runner, unauthenticated local HTTP endpoint or automatic execution of downloaded workflows. Presentation controls would need a visible armed mode and latency testing: brief Bluetooth sessions are not suitable for rapid keyboard-like input.

## Platform work

- Windows: reminder/alarm/settings editors, safe photo import, tray behavior and real Windows 11 high-DPI/accessibility acceptance tests.
- macOS: further keyboard/VoiceOver, sleep/wake and hardware testing on Apple silicon and Intel.
- Both: sanitized diagnostic export, additional verified device fixtures and signed stable distributions.

This watch protocol is not a general notification display. Chat-message streaming, arbitrary text overlays, continuous sensor feeds and firmware modification are outside scope.
