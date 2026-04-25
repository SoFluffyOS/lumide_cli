/// Small filesystem and process helpers for the CLI.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

String homeDirectoryPath() {
  final home = Platform.isWindows
      ? Platform.environment['USERPROFILE']
      : Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw const OSError('Home directory not set.');
  }
  return home;
}

String defaultMacOsInstallDirectory() {
  return '/Applications';
}

String defaultWindowsInstallDirectory() {
  final appData = Platform.environment['LOCALAPPDATA'];
  if (appData == null || appData.isEmpty) {
    return p.join(homeDirectoryPath(), 'AppData', 'Local');
  }
  return appData;
}

String defaultLinuxInstallDirectory() {
  return p.join(homeDirectoryPath(), '.local', 'share');
}

Future<void> extractArchive(String archivePath, String destinationDir) async {
  final bytes = await File(archivePath).readAsBytes();
  Archive? archive;

  if (archivePath.endsWith('.zip')) {
    archive = ZipDecoder().decodeBytes(bytes);
  } else if (archivePath.endsWith('.tar.gz') || archivePath.endsWith('.tgz')) {
    final gzBytes = GZipDecoder().decodeBytes(bytes);
    archive = TarDecoder().decodeBytes(gzBytes);
  }

  if (archive == null) {
    throw Exception('Unsupported archive format: $archivePath');
  }

  for (final file in archive) {
    final filename = file.name;
    if (file.isFile) {
      final data = file.content as List<int>;
      final outFile = File(p.join(destinationDir, filename));
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(data);

      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', outFile.path]);
      }
    } else {
      await Directory(p.join(destinationDir, filename)).create(recursive: true);
    }
  }
}

Future<void> ensureDirectoryExists(String path) async {
  final directory = Directory(path);
  if (await directory.exists()) {
    return;
  }
  await directory.create(recursive: true);
}

Future<void> runCheckedProcess(
  String executable,
  List<String> arguments, {
  String? failureMessage,
}) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode == 0) {
    return;
  }

  final stderrOutput = (result.stderr as Object?)?.toString().trim();
  final details = stderrOutput == null || stderrOutput.isEmpty
      ? 'Process exited with code ${result.exitCode}.'
      : stderrOutput;
  throw ProcessException(
    executable,
    arguments,
    failureMessage == null ? details : '$failureMessage $details',
    result.exitCode,
  );
}
