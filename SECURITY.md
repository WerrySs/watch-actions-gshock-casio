# Security policy

## Supported versions

Security fixes are applied to the latest development branch and the latest published release. Early preview builds may change their local data schema before `1.0.0`.

## Report a vulnerability

Do not open a public issue for a suspected vulnerability. Use [GitHub's private vulnerability reporting](https://github.com/WerrySs/watch-actions-gshock-casio/security/advisories/new) for this repository. If the private form is unavailable, ask the maintainer for a private reporting channel without including exploit details in the public request. Include the affected version, operating system, reproduction steps, and realistic impact. Do not include watch identifiers, personal reminder content, signing files, passwords, or tokens.

This is a personal project, without a guaranteed response time. Please allow time for investigation and a coordinated fix before disclosure.

## Security model

- A manually registered record cannot trigger computer actions.
- A physical watch must connect and then be explicitly trusted before automatic actions can run.
- Discovery never transfers a manual registration's identity or trust. Explicit linking resets action permission.
- Unknown/reserved Bluetooth reasons never trigger an action or settings write.
- Pending writes are scoped to a linked physical watch; legacy unassigned queues never execute.
- Actions are allowlisted and bounded; arbitrary shell commands are not supported.
- Keyboard actions use a fixed key catalog and bounded recordings (32 complete steps, 30 seconds, pauses capped at 2 seconds). Recording requires an explicit Record action in the focused editor, cancels on focus loss, and pauses watch-triggered actions. No global hook, arbitrary script or Unicode text insertion is installed. Playback requires trusted hardware or a manual Test, respects OS permissions, and checks focus/held keys before every step. A shortcut can still invoke sensitive commands: configure only sequences you understand and never enter secrets while recording.
- Layer switching is limited to recognized manual gestures and isolated per trusted physical watch. AUTO cannot switch modes; trust/relink changes and restart reset runtime modes.
- State, packets, text, and images are size-checked and normalized before use.
- Local state writes are atomic, and symbolic-link state paths are rejected.
- A failed state load/save pauses writes and actions instead of overwriting unreadable data with defaults.
- Bluetooth requests and helper processes have timeouts. Opening a user-selected application does not give WatchBridge ownership of its lifetime.
- Stable release publication requires platform signing and macOS notarization. Experimental betas may be unsigned and are clearly labeled; publishing one to a public repository requires a separate explicit workflow input.

Bluetooth device names and identifiers are not cryptographic proof of identity. Use this experimental bridge only with watches you control. The compatibility allowlist limits protocol scope, not radio-level impersonation.

Maintainers verify private vulnerability reporting, secret scanning, push protection, and branch protections during the [public-beta checklist](docs/PUBLIC_BETA_CHECKLIST.md). Some settings are unavailable while the repository is private on GitHub Free; do not assume a service is active merely because this policy exists. Dependency alerts, automated audits and full-history Gitleaks checks complement, but do not replace, human review. Scanner output is redacted and raw reports are not published. No audit can guarantee the absence of vulnerabilities.

WatchBridge cannot protect against a compromised operating system, malicious software already running as the same user, modified binaries, or physical radio attacks outside the operating system Bluetooth security model.
