# Security policy

## Supported versions

Security fixes are applied to the latest development branch and the latest published release. Early preview builds may change their local data schema before `1.0.0`.

## Report a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability reporting for this repository, or contact the repository owner privately if that feature is unavailable. Include the affected version, operating system, reproduction steps, and realistic impact. Do not include watch identifiers, personal reminder content, signing files, passwords, or tokens.

You should receive an acknowledgement within seven days. Please allow time for investigation and a coordinated fix before disclosure.

## Security model

- A manually registered record cannot trigger computer actions.
- A physical watch must connect and then be explicitly trusted before automatic actions can run.
- Actions are allowlisted and bounded; arbitrary shell commands are not supported.
- State, packets, text, and images are size-checked and normalized before use.
- Local state writes are atomic, and symbolic-link state paths are rejected.
- Bluetooth and process operations have timeouts.
- Release publication requires platform signing and macOS notarization.

WatchBridge cannot protect against a compromised operating system, malicious software already running as the same user, modified binaries, or physical radio attacks outside the operating system Bluetooth security model.
