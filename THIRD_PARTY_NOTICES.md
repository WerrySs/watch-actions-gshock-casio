# Third-party notices

WatchBridge is built with open-source dependencies recorded in `Cargo.lock` and with Apple platform frameworks supplied by macOS. Each dependency remains subject to its own license.

The Windows client uses Slint under the Slint Royalty-free Desktop, Mobile, and Web Applications License 2.0. Its required `AboutSlint` attribution is available from the top-level About screen. Slint's source remains available under its published license choices; WatchBridge does not expose Slint as a standalone toolkit.

The release process checks dependency licenses with `cargo-deny`. Full license texts and crate/version attribution are included in `THIRD_PARTY_LICENSES.txt`, generated using `cargo-about` from the locked macOS/Windows runtime dependency graph. CI verifies this file is up to date. The template omits local paths and unrelated Cargo metadata. Slint's custom-license text is included explicitly because cargo-about 0.9.2 omits that LicenseRef from automatic text output; `about.toml` checks its bundled source hashes.

CASIO and G-SHOCK are trademarks of their respective owner. Their names are not project dependencies or endorsements and are used only where needed to describe compatibility. The bundled watch illustration and application icon are generic, unbranded project assets.
