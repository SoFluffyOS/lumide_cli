## 1.2.0
- Install to a custom folder with `--install-dir`, which the CLI remembers, or point it at one with `LUMIDE_INSTALL_DIR`. A folder that already holds Lumide can be used without reinstalling.
- `lumide doctor` and the upgrade question show the installed and the latest Lumide version.
- `lumide doctor` checks the Dart that Lumide starts plugins with, `dart.exe` behind Flutter's `dart.bat` on Windows, and finds `flutter.bat`.
- Downloads retry on connection errors, resume where they stopped, and no longer hang on a stalled connection or slow down under the install screen on Windows.
- Upgrades keep the installed Lumide until the new one is in place.
- `install` notices a running Lumide before downloading: on Windows it asks you to close it, on macOS and Linux it asks whether to install anyway and restart.
- Commands exit as soon as they are done instead of waiting for the update check.
- `--silent` no longer replaces an existing installation unless `--force` is given.
- Fix installs from the 0.25 archives landing in `Lumide/Lumide/`, where the CLI could not find them. Installs in that layout are still found.
- Fix downloads freezing on Windows.
- Fix the Linux menu entry and icon with the current archive layout.
- Fix the CLI reporting its own version as an update.
- Refuse archive entries that point outside the install folder, an existing `Lumide` folder that isn't Lumide, and folders inside an installed Lumide.

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
