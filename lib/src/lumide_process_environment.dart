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
}
