/// Remembers a custom install directory chosen with `lumide install
/// --install-dir`, so later commands find Lumide without extra setup.
library;

import 'dart:convert';
import 'dart:io';

import 'package:lumide/src/io_helpers.dart';
import 'package:path/path.dart' as p;

const String _configFileName = 'config.json';
const String _installDirectoryKey = 'installDirectory';

/// Folder for the CLI's own settings.
///
/// Kept separate from the Lumide app folder, which `lumide install` replaces
/// on upgrade:
/// - Windows: `%LOCALAPPDATA%\lumide-cli` (local, because the saved path is
///   specific to this machine)
/// - macOS: `~/Library/Application Support/lumide-cli`
/// - Linux: `$XDG_CONFIG_HOME/lumide-cli`, or `~/.config/lumide-cli`
String lumideCliConfigDirectory({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final base = switch (os) {
    'windows' => defaultWindowsInstallDirectory(environment),
    'macos' => p.join(
        homeDirectoryPath(environment, os), 'Library', 'Application Support'),
    _ => xdgBaseDirectory('XDG_CONFIG_HOME', ['.config'], environment),
  };
  return p.join(base, 'lumide-cli');
}

File _configFile(Map<String, String>? environment) => File(p.join(
    lumideCliConfigDirectory(environment: environment), _configFileName));

Map<String, Object?> _readConfig(File file) {
  try {
    if (!file.existsSync()) return {};
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map<String, Object?> ? decoded : {};
  } catch (_) {
    // A missing, unreadable or corrupt file must never break the CLI.
    return {};
  }
}

/// The install directory saved by a previous `lumide install`, or `null`.
String? savedLumideInstallDirectory([Map<String, String>? environment]) {
  final File file;
  try {
    file = _configFile(environment);
  } on OSError {
    return null;
  }
  final value = _readConfig(file)[_installDirectoryKey];
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

/// Saves [installDirectory], or forgets it when `null`.
///
/// Writes to a temporary file first and then renames it, so an interrupted
/// write never leaves a half-written config behind.
Future<void> saveLumideInstallDirectory(
  String? installDirectory, [
  Map<String, String>? environment,
]) async {
  final file = _configFile(environment);
  final config = _readConfig(file);
  if (installDirectory == null) {
    if (!config.containsKey(_installDirectoryKey)) return;
    config.remove(_installDirectoryKey);
  } else {
    config[_installDirectoryKey] = installDirectory;
  }

  await file.parent.create(recursive: true);
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(
    const JsonEncoder.withIndent('  ').convert(config),
    flush: true,
  );
  await temp.rename(file.path);
}
