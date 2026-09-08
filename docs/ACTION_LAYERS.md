# Action modes and recorded keyboard shortcuts

Available in development builds after Beta 3. **The existing Beta 3 downloads do not contain these features.** Use a review archive from a successful CI run for the feature commit, or build that source. Review builds remain experimental and may be unsigned.

## Create modes for different tasks

Open **Actions → Action modes**. **Normal** is your default set of actions. **New mode** creates another set: name it, choose a color, and configure the actions below. You can add up to 100 named modes; this is a local-data safety bound, not a limit of one alternate.

- A numbered card represents each mode. Its border and **Editing actions below** label show which configuration you are editing.
- **ACTIVE** and **Dashboard watch** show the selected physical watch's current mode. Editing a card does **not** activate it.
- **Name & color** edits a named mode. Arrows change its place in the cycle. **Delete** asks for confirmation and deletes that mode's actions, not the other modes.
- **Next mode button** reserves FIND, TIME or CNCT in **every** mode. Each use advances once, eventually returning to Normal. **Disabled** restores that gesture's saved ordinary actions.
- Adding, deleting or reordering modes, changing the switch, app restart and **Reset to Normal** return watches to Normal. Renaming/recoloring a mode does not change its actions.

For example, reserve FIND:

| Gesture | Normal (blue) | Presentation (purple) | Music (green) |
| --- | --- | --- | --- |
| FIND | Next: Presentation | Next: Music | Next: Normal |
| TIME | Right arrow once | Right arrow twice | Play/pause |
| CNCT | Do nothing | Double Command | Toggle mute |

This is a **latched cycle**, not a held modifier. Supported watches report short Bluetooth connection reasons, not continuous button-down/button-up events. There is no firmware change or additional watch button. See [Compatibility](COMPATIBILITY.md).

Mappings are app-wide; the active mode is **session-only and isolated per explicitly trusted physical watch**. Changing the Dashboard favorite does not transfer its mode to another watch. Revoking trust or relinking clears that watch's mode. **AUTO always uses Normal and never switches.** Time sync and pending watch writes keep their existing rules, including when TIME or CNCT is reserved. One in-flight computer action or active recording blocks additional actions/mode changes.

## Record a keyboard action

1. Choose **Keyboard shortcut** on a gesture that is not the mode switch, then open its configuration.
2. Release held modifiers and click **Record**.
3. Press and release your keys. For double Command on macOS: **press ⌘, release, press ⌘, release**.
4. Click **Stop recording**. Review the numbered key cards and pause between them.
5. Click **Save shortcut**. Recording alone does not overwrite the saved action.

Record a single chord, modifier-only taps, repeated arrows, or a short sequence of different chords. Auto-repeat from holding a key is ignored. Chords use standard modifiers plus one main key; release that key before the next. Modifier-only taps preserve left/right identity; modifiers attached to a main key are normalized to the standard left-side keys.

**Esc**, closing the editor, losing window focus or the 30-second deadline cancels recording and keeps the previous draft. Recordings contain up to **32 complete steps**, at most 30 seconds of pauses, with inter-step delays bounded to 40–2,000 ms. Holds are not recorded: each playback tap has a balanced press/release, with no delay while keys are down.

**Double Command** (macOS), **Double Windows** (Windows) and **Right twice** presets avoid having to record OS-reserved gestures. **Add a key manually** supports keys such as Escape (which cancels capture) and 1–10 repeated complete chords; **Undo last** removes the final draft step. A preset replaces the draft; manual additions append.

Some global/system shortcuts are handled by the OS or another app before this editor can consume them. They may change focus and cancel capture. Use a preset/manual entry in that case. Windows-key taps may open Start; Command double-tap behavior depends on the target utility. **Do not assume an app accepts synthetic input just because the sequence can be saved.**

Recording is explicitly **window-local**: AppKit local events on macOS and this Slint/winit window's physical key events on Windows. There is no global keyboard hook, text field/clipboard reader or background key log. Do not enter passwords or other secrets during recording. Raw transitions stay in memory and are discarded; only the reviewed key IDs, modifiers and bounded pauses are saved.

The shared 81-key catalog covers common US-reference physical positions, F1–F12, navigation and left/right Control, Alt/Option, Shift and Windows/Command. Your keyboard layout determines printable characters; labels are not a live layout translation. Fn, Caps Lock, extra ISO/numpad keys, secure system sequences and Unicode text insertion are not supported.

## macOS mode indicator

The **Floating mode indicator** option shows a small black capsule below the primary screen's menu bar, with the same watch symbol as the menu-bar item and the Dashboard watch's mode name/color. The menu-bar symbol also uses the mode color; Normal is blue.

It uses the usable screen area rather than notch coordinates, so it works with or without a notch and keeps clear of the menu bar. It does not take keyboard focus or intercept clicks. Turn it off from Action modes if it covers content you need. It describes the Dashboard watch's session mode, **not continuous Bluetooth connectivity**, and does not imply that watch data is live. Display scaling, full-screen Spaces, multiple displays and menu-bar color rendering still need interactive acceptance on real Macs. No Windows notch/floating overlay is added.

## Test safely

**Test waits three seconds** for keyboard actions. Focus a harmless document/test window and release all held modifiers. Physical-watch actions do not have that manual delay.

Input targets the app focused when playback starts. WatchBridge refuses self-targeting and rechecks focus and relevant held keys before every step, after any pause. A focus change or held key stops the remaining sequence; input already delivered cannot be undone. Use a single step for shortcuts that intentionally change focus.

- **macOS:** user-granted Accessibility permission is required for native Core Graphics playback. Recording local editor events does not require a global keyboard-monitoring permission.
- **Windows:** native SendInput is not elevated. Administrator apps and secure desktops remain unsupported. Partial insertion triggers best-effort release of only keys still held by this request; the OS can also reject cleanup.

OS focus races and target rejection remain possible. A “request sent” result is not proof of acceptance. Do not test destructive shortcuts or use these experimental actions for safety-critical tasks.

## Upgrade and rollback

Existing Normal actions, the original Alternate actions, switch choice, old key-picker shortcuts and time-sync settings migrate without reassigning gestures. Existing Alternate becomes the first named mode.

Windows saves schema **4**; schema-2 and schema-3 clients refuse newer state. macOS reads the legacy configuration once and writes **config-v2.json**, leaving **config.json** untouched. If the newer file is corrupt, it does not silently fall back to the old one. Older macOS builds see only their legacy configuration, not subsequent mode/shortcut edits. Do not alternate versions against the same data folder.

Back up the complete app-data folder before upgrading. Formats are platform-specific and cannot be interchanged. Invalid recordings/unknown profile IDs fail closed; they never fall back to a default arrow or write into Normal.

## Validation

Unit tests validate recorder transitions, double modifier taps, cancellation bounds, migration, multiple-mode cycling/order/trust isolation and balanced native input plans. Sample-data screenshots cover the editor, manual controls, mode management and indicator at bounded sizes. They do **not** certify real keyboard injection or Bluetooth hardware behavior.

Interactive acceptance remains required for double Command in your chosen utility, focused-window behavior, permission/secure-target rejection, non-US layouts, AltGr, display scaling and the macOS indicator. Record evidence in the [hardware validation issue](https://github.com/WerrySs/watch-actions-gshock-casio/issues/2). See [Security](../SECURITY.md) and [Privacy](../PRIVACY.md).
