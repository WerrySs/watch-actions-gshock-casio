# Privacy

WatchBridge is local-first and does not operate a backend service.

## Data stored locally

Depending on the features used, the app may store:

- watch identifiers, detected and configured models, and optional nicknames;
- cached battery, temperature, city, timer, alarm, reminder, and settings values;
- pending changes and configured computer actions;
- reviewed keyboard key IDs, modifiers, bounded pauses/repetitions, named mode colors and action mappings (active session modes are not persisted);
- connection timestamps, outcomes, and bounded diagnostic messages; and
- user-selected watch photos after local sanitization.

macOS stores these files under the current user's Application Support directory. Windows stores them in the current user's local application data directory. State is capped at 10 MB, history is capped in the model, and imported images are copied into an app-owned directory.

## Data not collected

The project contains no analytics, advertising, crash-upload, tracking, account, or cloud-synchronization SDK. WatchBridge does not upload watch data or photos. Normal operating-system services may still be involved when you explicitly open a web link, run a Shortcut, use text-to-speech, or ask the operating system to open another application.

The shortcut recorder consumes key events only while you explicitly record inside the focused editor. It does not install a global keyboard hook or read text fields, clipboard contents, or another application's input. Escape, closing, losing focus or 30 seconds cancels capture. Do not enter passwords or personal text while recording. Raw key transitions are temporary; only the reviewed key IDs, modifiers and bounded pauses are saved after Save. Recorder errors and action logs do not include recorded keys or mode names.

Before playback, WatchBridge checks the focused app/window and relevant held keys, without retaining a history of foreground apps. The receiving app handles synthetic keys according to its own behavior and privacy policy. The optional macOS indicator draws a click-through window; it does not capture the screen or monitor other apps.

## User-supplied images

On macOS, WatchBridge accepts a regular local image up to 20 MB and 50 megapixels. It decodes the first frame, scales it to at most 2,400 pixels per side, and writes a new PNG with a generated filename. EXIF, GPS, and the original filename are not copied. Removing a saved photo removes the app-owned copy.

## Removal

Removing a watch from within the app removes its local record and app-owned photo. Uninstalling the executable does not automatically remove operating-system application-data folders; delete the WatchBridge data folder separately if you want to erase all local state.
