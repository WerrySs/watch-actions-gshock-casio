# Action layers and keyboard shortcuts

Available in development builds after Beta 3. The existing **Beta 3 download does not contain these features**; use the macOS or Windows review archive from a successful CI run for the feature commit, or build that source. Review builds remain experimental and may be unsigned.

## Two sets of actions from the same watch

Open **Actions → Action layers**, then choose **FIND**, **TIME** or **CNCT** in **Switch modes with**. Select **Normal** or **Alternate** under **Editing layer** and configure each gesture's computer action.

The switch gesture is reserved in **both** layers. It toggles the mode instead of running its saved computer action, so the same gesture always switches back. Choosing **Disabled** restores ordinary gesture actions and resets every watch to Normal. Saved mappings are retained.

For example, choose FIND as the switch:

| Gesture | Normal | Alternate |
| --- | --- | --- |
| FIND | Switch to Alternate | Switch to Normal |
| TIME | Right arrow ×1 | Right arrow ×2 |
| CNCT | Do nothing | Play or pause media |

This is a **latched mode**, not a held modifier. The supported watches report short Bluetooth connection reasons, not continuous button-down/button-up events. No firmware change or extra watch button is created. The physical procedures are in [Compatibility](COMPATIBILITY.md).

Action mappings are app-wide, but the active mode belongs to each **explicitly trusted physical watch**, in memory only. Another watch or Dashboard favorite does not inherit it. App restart, changing the switch gesture, relinking, changing trust, or **Reset to Normal** clears the corresponding mode. The Dashboard shows the selected watch's active mode; the Actions page distinguishes that from the layer being edited. Changing the editing selector does not change a watch's active mode.

**AUTO always uses Normal and never switches modes.** Time synchronization and queued watch writes keep their existing rules, including when TIME or CNCT is the switch. One in-flight computer action blocks overlapping actions and mode switches; consult the activity log if a gesture was ignored.

## Build a keyboard action

1. Choose **Keyboard shortcut** for a gesture that is not the mode switch.
2. Open its keyboard configuration button. Click a key on the visual keyboard.
3. Add Control, Alt/Option, Shift and/or Windows/Command modifiers, if needed.
4. Set **Repeat** to **1–10**, then **Save shortcut**.

Each repeat presses and releases the complete chord. Repeats are separated by 100 ms. For the example above, select the right-arrow key and set Repeat to 2. The preview shows **→ ×2**. Selecting keys is local; the editor does not listen to or record your typing.

The catalog covers letters, digits, common punctuation, F1–F12, Escape, Tab, Enter, Space, Backspace and navigation/arrow keys. Labels use **US reference physical positions**, not a live layout translation. Your active keyboard layout determines printable characters. Fn, Caps Lock, extra ISO/numpad keys, secure system sequences, arbitrary text and multi-step macros are outside this first version.

## Test safely

**Test waits three seconds** for a keyboard action. Focus a harmless document or test window, release held modifiers, and wait. Physical-watch actions do not have that manual-test delay.

Keys go to the application focused when sending begins, not to a permanently bound app. WatchBridge refuses to send them to itself and checks the target again before every repetition. A foreground-app change on macOS, a foreground-window change on Windows, or held modifiers/the selected key stops the remaining repetitions. These checks reduce accidental input; they cannot remove all OS focus races or undo input already delivered. Use single presses for shortcuts that intentionally change focus.

- **macOS:** grant WatchBridge Accessibility permission in System Settings yourself. The editor links to that settings page; it does not grant permission or install a keyboard hook. Input uses the native Core Graphics API.
- **Windows:** input uses the native `SendInput` API without elevation. Administrator apps and secure desktops are not supported. A partial insertion gets a best-effort release of only the keys this action still holds; Windows may also reject cleanup.

Operating systems and target apps may reject or reinterpret synthetic input. A “request sent” result is not proof that the target accepted it. Do not test destructive shortcuts or rely on these experimental actions for safety-critical tasks. Review [Security](../SECURITY.md) before authorizing a watch.

## Existing settings and upgrades

Existing Normal actions and time-sync settings are preserved. Alternate starts empty, with switching disabled. Invalid key IDs or repeat counts do not execute. Windows advances its state to schema 3 on save, so older schema-2 builds refuse to overwrite it.

Back up the local data folder before trying a development build or downgrading. macOS retains its separate Codable configuration format: older builds cannot understand keyboard actions and may discard new layer fields if no keyboard action is present. Downgrades and cross-platform state-file copying are not supported; restore the matching backup instead. See [Installation](INSTALLATION.md).

## Verification scope

Automated tests cover legacy configuration, mode isolation, trust, switching back, AUTO routing, bounded keys/repeats, and balanced native event plans. Tests do **not** inject shortcuts into an uncontrolled desktop. Sample-data screenshots check layout, not permissions or actual watch behavior. Manual keyboard/focus/permission tests and physical BLE acceptance on both operating systems remain necessary; record them through the [hardware validation issue template](https://github.com/WerrySs/watch-actions-gshock-casio/issues/new?template=hardware-validation.yml).

Platform behavior is documented by [Apple's Core Graphics keyboard events](https://developer.apple.com/documentation/coregraphics/cgevent), [Accessibility trust](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted), [Microsoft SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput) and [KEYBDINPUT scan-code flags](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-keybdinput).
