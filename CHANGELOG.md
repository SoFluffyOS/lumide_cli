## Unreleased
- Fix installs from the 0.25 archives landing in `Lumide/Lumide/`, so the CLI could not find the app it had just installed. Existing installs in that layout are still found.
- Fix downloads freezing (nocterm 0.8) and running about 16x slower under the install screen on Windows (download and extraction now run on a background isolate).
- Retry the release lookup and download on connection errors, resume interrupted downloads, and fail stalled connections instead of hanging.
- Commands exit as soon as they are done instead of waiting for the update check.
- `--silent` no longer replaces an existing installation unless `--force` is given.
- Refuse archive entries that would extract outside the install folder.
- Never replace an existing `Lumide` folder that is not a Lumide installation (it was deleted before), and refuse to install inside an installed Lumide.
- Linux: add the app menu entry and icon from the current archive layout.
- Add `LUMIDE_INSTALL_DIR`, and remember a custom `--install-dir` so `lumide`, `launch` and `doctor` find Lumide there. A folder that already holds Lumide can be used without reinstalling.
- `lumide doctor` and the upgrade question show the installed and latest Lumide versions.
- Fix the CLI reporting its own current version as an available update.
- `lumide doctor` checks the Dart that Lumide starts plugins with: the `dart` on its PATH, and on Windows the `dart.exe` behind Flutter's `dart.bat`, instead of the one the CLI itself runs in. The Flutter check now finds `flutter.bat`.

## 1.1.1
- Add `-n` arg for macOS to open as new process.

## 1.1.0+1
- Add more verbose diagnostics in `lumide doctor` command. Use `lumide doctor --verbose`.

## 1.0.0+1

- **Initial Stable Release!**
- Full cross-platform support (macOS, Windows, Linux).
- Integrated adaptive TUI for the `install` command.
- Added `lumide doctor` for system diagnostics.
- Implemented smart argument passthrough and auto-install redirection.
- Added `--silent` flag for non-interactive installations.
- Automated version check via pub.dev API.
- Integrated Linux desktop environment support (.desktop file and icons).
