import 'dart:io';

import 'package:path/path.dart' as p;

/// Reproduces the environment Lumide passes to child processes.
class LumideProcessEnvironment {
  LumideProcessEnvironment._();

  static String _shellPath = '';
  static final Map<String, String> _shellEnvironment = {};

  static Future<void> initialize() async {
    _shellEnvironment.clear();

    if (Platform.isWindows) {
      _shellPath = Platform.environment['Path'] ?? '';
      return;
    }

    try {
      final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
      final result = await Process.run(
        shell,
        ['-ilc', 'env'],
        runInShell: false,
      ).timeout(const Duration(seconds: 3));

      if (result.exitCode != 0) {
        _shellPath = Platform.environment['PATH'] ?? '';
        return;
      }

      for (final line in result.stdout.toString().split('\n')) {
        final parts = line.split('=');
        if (parts.length < 2) continue;
        final key = parts.first;
        final value = parts.sublist(1).join('=');
        _shellEnvironment[key] = value;
      }
      _shellPath = _shellEnvironment['PATH'] ?? '';
    } catch (_) {
      _shellPath = Platform.environment['PATH'] ?? '';
    }
  }

  static Map<String, String> get environment {
    final result = Map<String, String>.from(Platform.environment);
    result.addAll(_shellEnvironment);

    final pathKey = Platform.isWindows ? 'Path' : 'PATH';
    if (_shellPath.isNotEmpty) result[pathKey] = _shellPath;
    return result;
  }

  static String get path => environment['PATH'] ?? environment['Path'] ?? '';

  /// Matches Lumide's executable lookup, including its Windows extension order.
  static Future<String?> resolveExecutable(String executable) async {
    if (p.isAbsolute(executable)) {
      return await File(executable).exists() ? executable : null;
    }

    final separator = Platform.isWindows ? ';' : ':';
    final extensions =
        Platform.isWindows ? const ['.exe', '.bat', '.cmd', ''] : const [''];
    for (final directory in path.split(separator)) {
      if (directory.trim().isEmpty) continue;
      for (final extension in extensions) {
        final candidate = p.join(directory, '$executable$extension');
        final file = File(candidate);
        if (!await file.exists()) continue;
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.file) return candidate;
      }
    }
    return null;
  }

  /// What a bare `dart` started by Lumide.exe gets on Windows.
  ///
  /// Windows (`CreateProcess`) starts a bare command name only as an
  /// `.exe`, looking in the starting program's own folder ([appFolder])
  /// before [pathEntries] (by default Lumide's PATH), so a `dart.bat`
  /// (Flutter's wrapper in `flutter\bin`) is never run. [exe] is the
  /// `dart.exe` found; when there is none, [batch] is the `dart.bat` or
  /// `dart.cmd` on the PATH and [sdkBin] the folder of the `dart.exe`
  /// behind it (Flutter keeps it in `bin\cache\dart-sdk\bin`), if present.
  static ({String? exe, String? batch, String? sdkBin}) windowsDart({
    String? appFolder,
    List<String>? pathEntries,
  }) {
    if (appFolder != null) {
      final bundled = p.join(appFolder, 'dart.exe');
      if (File(bundled).existsSync()) {
        return (exe: bundled, batch: null, sdkBin: null);
      }
    }
    final directories = (pathEntries ?? path.split(';'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty);
    String? batch;
    for (final directory in directories) {
      final exe = p.join(directory, 'dart.exe');
      if (File(exe).existsSync()) return (exe: exe, batch: null, sdkBin: null);
      batch ??= [p.join(directory, 'dart.bat'), p.join(directory, 'dart.cmd')]
          .where((candidate) => File(candidate).existsSync())
          .firstOrNull;
    }
    if (batch == null) return (exe: null, batch: null, sdkBin: null);
    final sdkBin = p.join(p.dirname(batch), 'cache', 'dart-sdk', 'bin');
    return (
      exe: null,
      batch: batch,
      sdkBin: File(p.join(sdkBin, 'dart.exe')).existsSync() ? sdkBin : null,
    );
  }

  /// The environment change to start Lumide at [appPath] with on Windows,
  /// or `null` to start it with the current environment unchanged.
  ///
  /// When Lumide would find no `dart.exe` ([windowsDart]) but PATH has
  /// Flutter's `dart.bat`, the Flutter SDK's own `bin\cache\dart-sdk\bin`
  /// is appended to Lumide's PATH, so its plugin loader can start `dart`.
  /// Appended last, it changes nothing that already resolves; only that
  /// Lumide process is affected.
  static Map<String, String>? windowsLaunchEnvironment(String appPath) {
    if (!Platform.isWindows) return null;
    return launchEnvironmentWithDart(
      Platform.environment,
      appFolder: p.dirname(appPath),
    );
  }

  /// [windowsLaunchEnvironment] for a given [environment].
  static Map<String, String>? launchEnvironmentWithDart(
    Map<String, String> environment, {
    String? appFolder,
  }) {
    final key = environment.keys.firstWhere(
      (name) => name.toLowerCase() == 'path',
      orElse: () => 'Path',
    );
    final current = environment[key] ?? '';
    final dart = windowsDart(
      appFolder: appFolder,
      pathEntries: current.split(';'),
    );
    final sdkBin = dart.sdkBin;
    if (dart.exe != null || sdkBin == null) return null;
    return {key: current.isEmpty ? sdkBin : '$current;$sdkBin'};
  }
}
