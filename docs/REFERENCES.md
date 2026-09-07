# References and acknowledgements

Reviewed 2026-09-07. These sources describe hardware and related implementations; they do not imply endorsement or certify WatchBridge.

## Official hardware references

- [GW-B5600 family](https://gshock.casio.com/mea-en/products/collection/origin/gw-b5600/): Mobile Link capabilities.
- [GW-B5600BP-1 support](https://www.casio.com/sg/watches/casio/support.GW-B5600BP-1/): exact-model manual entry point.
- [3459/3461 operation guide](https://support.casio.com/global/en/wat/manual/3461_en/): controls and limits.
- [Phone Finder](https://support.casio.com/global/en/wat/manual/3461_en/VPCVSYjtigotoo.html): D-button FIND procedure.
- [Connection/pairing](https://support.casio.com/global/en/wat/manual/3461_en/VPCVSYoxhqhxmg.html): C-button CNCT procedure.
- [TIME & PLACE](https://support.casio.com/global/en/wat/manual/3461_en/VPCVSYauwrsrwy.html): short D-button phone workflow.
- [Reminder settings](https://support.casio.com/global/en/wat/manual/3461_en/KPNDSYfxxordgr.html): five reminder slots and 18-character alphanumeric titles.
- [Automatic time adjustment](https://support.casio.com/global/en/wat/manual/3461_en/VPCVSYpdressau.html): scheduled connections.

These describe Casio's official phone software, not a public desktop BLE API. Manufacturer photos/manuals are linked, not bundled.

## Related work and platform APIs

- [Casio G-Shock Smart Sync by izivkov](https://github.com/izivkov/CasioGShockSmartSync): independent Android synchronization and remote-action project. A useful research reference, not a bundled dependency or a compatibility list to copy.
- [btleplug](https://github.com/deviceplug/btleplug): the Rust host-side BLE library used by the Windows client.
- [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth): macOS transport API.
- [Microsoft Bluetooth LE](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/bluetooth-low-energy-overview): Windows GATT communication.
- [Slint desktop documentation](https://docs.slint.dev/latest/docs/slint/guide/platforms/desktop/): UI toolkit, distinct from WinUI controls.

Linking a project does not grant permission to copy its code/assets. Review licensing and attribution before reuse. Actual dependency notices are in [Third-party notices](../THIRD_PARTY_NOTICES.md).
