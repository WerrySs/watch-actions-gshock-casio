# Privacy

WatchBridge is local-first and does not operate a backend service.

## Data stored locally

Depending on the features used, the app may store:

- watch identifiers, detected and configured models, and optional nicknames;
- cached battery, temperature, city, timer, alarm, reminder, and settings values;
- pending changes and configured computer actions;
- connection timestamps, outcomes, and bounded diagnostic messages; and
- user-selected watch photos after local sanitization.

macOS stores these files under the current user's Application Support directory. Windows stores them in the current user's local application data directory. State is capped at 10 MB, history is capped in the model, and imported images are copied into an app-owned directory.

## Data not collected

The project contains no analytics, advertising, crash-upload, tracking, account, or cloud-synchronization SDK. WatchBridge does not upload watch data or photos. Normal operating-system services may still be involved when you explicitly open a web link, run a Shortcut, use text-to-speech, or ask the operating system to open another application.

## User-supplied images

On macOS, WatchBridge accepts a regular local image up to 20 MB and 50 megapixels. It decodes the first frame, scales it to at most 2,400 pixels per side, and writes a new PNG with a generated filename. EXIF, GPS, and the original filename are not copied. Removing a saved photo removes the app-owned copy.

## Removal

Removing a watch from within the app removes its local record and app-owned photo. Uninstalling the executable does not automatically remove operating-system application-data folders; delete the WatchBridge data folder separately if you want to erase all local state.
