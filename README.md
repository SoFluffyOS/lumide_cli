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

---

## Happy Coding! 🦊❤️

Made with ❤️ by **SoFluffy**
