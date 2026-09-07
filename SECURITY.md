# Security policy

## Supported versions

Security fixes are applied to the latest development branch and the latest published release. Early preview builds may change their local data schema before `1.0.0`.

## Report a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability reporting for this repository, or contact the repository owner privately if that feature is unavailable. Include the affected version, operating system, reproduction steps, and realistic impact. Do not include watch identifiers, personal reminder content, signing files, passwords, or tokens.

This is a personal project, without a guaranteed response time. Please allow time for investigation and a coordinated fix before disclosure.

## Security model

- A manually registered record cannot trigger computer actions.
- A physical watch must connect and then be explicitly trusted before automatic actions can run.
- Discovery never transfers a manual registration's identity or trust. Explicit linking resets action permission.
- Unknown/reserved Bluetooth reasons never trigger an action or settings write.
- Pending writes are scoped to a linked physical watch; legacy unassigned queues never execute.
- Actions are allowlisted and bounded; arbitrary shell commands are not supported.
- State, packets, text, and images are size-checked and normalized before use.
- Local state writes are atomic, and symbolic-link state paths are rejected.
- A failed state load/save pauses writes and actions instead of overwriting unreadable data with defaults.
- Bluetooth requests and helper processes have timeouts. Opening a user-selected application does not give WatchBridge ownership of its lifetime.
- Stable release publication requires platform signing and macOS notarization. Private previews may be unsigned and are clearly labeled.

Bluetooth device names and identifiers are not cryptographic proof of identity. Use this experimental bridge only with watches you control. The compatibility allowlist limits protocol scope, not radio-level impersonation.

Private vulnerability reporting and secret scanning may be unavailable under the current GitHub plan; do not assume those services are active merely because this policy exists. Dependency alerts, automated audits and repository credential-pattern checks complement, but do not replace, human review. No audit can guarantee the absence of vulnerabilities.

WatchBridge cannot protect against a compromised operating system, malicious software already running as the same user, modified binaries, or physical radio attacks outside the operating system Bluetooth security model.
