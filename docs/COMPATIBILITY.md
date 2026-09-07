# Compatibility and physical buttons

Only the implemented **GW-B5600 / module 3461** target is admitted. The current allowlist contains GW-B5600, GW-B5600-2, GW-B5600BC-1B, GW-B5600HR-1, GW-B5600BL-1, GW-B5600BP-1 and GW-B5600MG-1, with recognized regional suffixes. This is an implementation target list, not a claim that every variant was physically tested on both OSes.

| Platform | Implementation | Hardware acceptance |
| --- | --- | --- |
| macOS | SwiftUI/CoreBluetooth with shared Rust codecs | Exact-model end-to-end test report pending |
| Windows | Rust/Slint/Windows BLE | Exact-model end-to-end test report pending |

No fully verified model/platform matrix is claimed yet. Do not add other Casio families based only on a Bluetooth logo, a shared service or another project's support list. Discovery and registration now use the same Rust allowlist. A manual record cannot execute actions or queue writes until explicitly associated with a physical watch.

## Button guide

With the watch upright: A is upper left, B upper right, C lower left and D lower right. Use the timekeeping screen.

| Gesture | Indication | App interpretation |
| --- | --- | --- |
| Hold C about 3 seconds | CNCT | Full connection; scoped pending changes can be sent |
| Brief press D | TIME | Time-related connection/action |
| Hold D about 5 seconds | FIND | Finder-related connection/action |
| Scheduled connection | AUTO | Automatic time adjustment; not a button press |

The [official 3459/3461 guide](https://support.casio.com/global/en/wat/manual/3461_en/) documents the phone workflow. Computer-action mapping is WatchBridge behavior, not an official Casio capability guarantee. See [References](REFERENCES.md) for each procedure.

These are intermittent connection reasons, not continuous remote keyboard events from every button. Bluetooth discovery takes time and another connected phone/app can prevent the session. Unknown reason values cause no action or settings write. Name filtering is not cryptographic authentication; OS device identity and explicit user trust remain separate boundaries.

## Adding a model

Submit the exact model/module, official manual, app commit, OS/architecture and separate results for FIND/TIME/CNCT. Test trust blocking, unknown events, reconnect, cache after restart, and per-device write isolation. Do not attach serial numbers, Bluetooth identifiers, personal reminder contents or unredacted captures. Add protocol code and regression tests before expanding the allowlist.
