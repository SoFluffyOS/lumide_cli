# Lumide CLI

[![pub package](https://img.shields.io/pub/v/lumide.svg)](https://pub.dev/packages/lumide)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Platform](https://img.shields.io/badge/platform-windows%20%7C%20macos%20%7C%20linux-lightgrey)

`lumide` is a delightful cross-platform CLI for installing, managing, and launching [Lumide](https://lumide.dev).

Built for speed and developer happiness, the Lumide CLI ensures you spend less time setting up and more time coding.

## Features

- **Cross-Platform**: Support for macOS (DMG), Windows (Zip), and Linux (Zip/Tar.gz).
- **Beautiful TUI**: Powered by [nocterm](https://pub.dev/packages/nocterm) terminal interface with smooth animations.
- **Smart Path Resolution**: Launch into any directory with `lumide .`—handles absolute paths and case-sensitivity automatically.
- **Auto-Install**: Smart detection offers to set up Lumide if it's missing when you try to launch.
- **Health Checks**: `lumide doctor` helps diagnose your environment and SDK paths.
- **Desktop Integration**: Automatic `.desktop` entry and icon setup for Linux users.

## Installation

```bash
dart pub global activate lumide
```

## Quick Start

```bash
# Launch Lumide in the current directory (installs if missing!)
lumide .

# Check your environment
lumide doctor

# Show the environment and executable resolution used for plugin startup
lumide doctor --verbose

# Reproduce plugin dependency startup with Lumide's process configuration
lumide doctor --verbose --dart-path <configured-dart> --plugin-path <plugin-dir>

# Just install/update
lumide install

# Perform a silent installation
lumide install --silent
```

## Commands

| Command | Description |
|---------|-------------|
| `lumide launch <path>` | Open a directory or file in Lumide (default command). |
| `lumide install` | Download and set up the latest Lumide release. |
| `lumide doctor` | Verify installation status and system SDKs. |
| `lumide help` | Show available commands and options. |

## Options

- `-s, --silent`: Skip the terminal UI for automated installs.
- `--install-dir`: Specify a custom installation location.
- `--force`: Force a fresh installation over an existing one.

### Custom install location

By default Lumide lives in `%LOCALAPPDATA%\Lumide` on Windows,
`/Applications` on macOS and `~/.local/opt/lumide` on Linux. To keep it
somewhere else, install it there once:

```bash
lumide install --install-dir D:\Tools    # Lumide in D:\Tools\Lumide\Lumide.exe
```

The CLI remembers the folder, so `lumide`, `lumide launch`, `lumide doctor`
and later `lumide install` runs use it automatically. Installing again into
the default location forgets it. The setting is stored in
`%LOCALAPPDATA%\lumide-cli\config.json` (Windows),
`~/Library/Application Support/lumide-cli/config.json` (macOS) or
`$XDG_CONFIG_HOME/lumide-cli/config.json` (Linux, default `~/.config`).

Already have Lumide in that folder (for example one you unzipped yourself)?
Run the same command and answer **No** to the upgrade question: the CLI
then offers to use that copy from now on, without downloading anything.

You can also set `LUMIDE_INSTALL_DIR`, for example for CI or a shared setup.
It takes priority over the remembered folder:

```bash
# Windows (PowerShell)
setx LUMIDE_INSTALL_DIR "D:\Tools"

# macOS / Linux
export LUMIDE_INSTALL_DIR="$HOME/Apps"
```

Order of precedence: `--install-dir` (install only), then
`LUMIDE_INSTALL_DIR`, then the remembered folder, then the default.
`lumide doctor` shows which one is in use.

On Windows and Linux the folder can also be the app's own folder, so a
release archive you unzipped yourself works too. The CLI checks these
places in order (a fixed list, not a search) and uses the first that
exists; the second is the layout older CLI versions created:

| Platform | Checked, in order                                                                       |
| -------- | --------------------------------------------------------------------------------------- |
| Windows  | `<dir>\Lumide\Lumide.exe`, `<dir>\Lumide\Lumide\Lumide.exe`, `<dir>\Lumide.exe`          |
| macOS    | `<dir>/Lumide.app` (for the default folder, also `~/Applications/Lumide.app`)           |
| Linux    | `<dir>/lumide/Lumide`, `<dir>/lumide/Lumide/Lumide`, `<dir>/Lumide`, `<dir>/Lumide/Lumide` |

If none exists, `lumide doctor` lists every path it checked. A copy found
outside the folder `lumide install` manages (e.g. `<dir>\Lumide.exe`) is
never replaced; installing then adds a separate copy, after asking.

Pointing at an installed Lumide's own folder (`D:\Tools\Lumide`) means the
same as its install folder (`D:\Tools`). To protect your files,
`lumide install` refuses a folder inside an installed Lumide (upgrades
replace that whole folder), and never replaces an existing `Lumide` folder
that isn't a Lumide installation.

### Plugin startup diagnostics

`lumide doctor --verbose` resolves bare `dart` using the same environment and
Windows executable-extension order as Lumide. Pass `--dart-path` to compare a
custom Dart SDK setting. Pass `--plugin-path` to run the exact `dart pub get`
process used when starting a local plugin, including its working directory.
Verbose output summarizes PATH and shows only Dart/Flutter entries; add
`--show-path` when the complete PATH is needed.

---

## Happy Coding! 🦊❤️

Made with ❤️ by **SoFluffy**
