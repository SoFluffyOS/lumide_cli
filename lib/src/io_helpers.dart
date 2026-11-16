/// Small filesystem and process helpers for the CLI.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

String homeDirectoryPath([
  Map<String, String>? environment,
  String? operatingSystem,
]) {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;
  final home = os == 'windows' ? env['USERPROFILE'] : env['HOME'];
  if (home == null || home.isEmpty) {
    throw const OSError('Home directory not set.');
  }
  return home;
}

String defaultMacOsInstallDirectory() {
  return '/Applications';
}

String defaultWindowsInstallDirectory([Map<String, String>? environment]) {
  final appData = (environment ?? Platform.environment)['LOCALAPPDATA'];
  if (appData == null || appData.trim().isEmpty) {
    return p.join(
        homeDirectoryPath(environment, 'windows'), 'AppData', 'Local');
  }
  return appData.trim();
}

String defaultLinuxInstallDirectory() {
  return p.join(homeDirectoryPath(), '.local', 'share');
}

/// An XDG base directory: `$variable` when it is an absolute path (the spec
/// says to ignore relative ones), else `~/<fallback>`.
String xdgBaseDirectory(
  String variable,
  List<String> fallback, [
  Map<String, String>? environment,
]) {
  final value = (environment ?? Platform.environment)[variable]?.trim();
  if (value != null && value.isNotEmpty && p.isAbsolute(value)) return value;
  return p.joinAll([homeDirectoryPath(environment, 'linux'), ...fallback]);
}

/// `$XDG_DATA_HOME`, by default `~/.local/share`.
String linuxDataHome([Map<String, String>? environment]) =>
    xdgBaseDirectory('XDG_DATA_HOME', ['.local', 'share'], environment);

/// Extracts [archivePath] (.zip or .tar.gz) into [destinationDir].
///
/// If every entry sits in one top-level folder (the release archives wrap
/// everything in `Lumide/`), that folder is dropped, like
/// `tar --strip-components=1`.
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

  // Check every entry before writing anything, so a malicious archive
  // ("zip slip": names like ../../x or absolute paths) cannot write outside
  // the destination and leaves nothing half-extracted.
  final root = p.normalize(p.absolute(destinationDir));
  final wrapper = singleTopLevelDirectory(archive.map((file) => file.name));

  final entries = <(ArchiveFile, String)>[];
  for (final file in archive) {
    var name = normalizeArchiveEntryName(file.name);
    if (wrapper != null) {
      // The wrapper folder itself, and junk outside it (e.g. __MACOSX/).
      if (!name.startsWith('$wrapper/')) continue;
      name = name.substring(wrapper.length + 1);
      if (name.isEmpty) continue;
    }
    entries.add((file, archiveEntryTarget(root, name)));
  }

  for (final (file, target) in entries) {
    if (file.isFile) {
      final data = file.content as List<int>;
      final outFile = File(target);
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(data);

      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', outFile.path]);
      }
    } else {
      await Directory(target).create(recursive: true);
    }
  }
}

/// [name] with `/` as the separator (some Windows tools write `\`) and
/// without leading `./` segments.
String normalizeArchiveEntryName(String name) {
  var normalized = name.replaceAll(r'\', '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  return normalized;
}

/// The one folder that every entry in [entryNames] sits in, or `null` when
/// the entries are spread over several top-level items or the only one is
/// a file. macOS metadata (`__MACOSX/`, `.DS_Store`) is ignored.
String? singleTopLevelDirectory(Iterable<String> entryNames) {
  String? top;
  var hasContent = false;
  for (final rawName in entryNames) {
    final name = normalizeArchiveEntryName(rawName);
    if (name.isEmpty || name == '.') continue;
    final slash = name.indexOf('/');
    final first = slash < 0 ? name : name.substring(0, slash);
    if (first == '__MACOSX' || first == '.DS_Store') continue;
    // An absolute name (leading '/') gives an empty first segment, so it is
    // never stripped; archiveEntryTarget rejects it.
    if (first.isEmpty || first == '..') return null;
    if (top == null) {
      top = first;
    } else if (top != first) {
      return null;
    }
    if (slash >= 0 && slash < name.length - 1) hasContent = true;
  }
  return hasContent ? top : null;
}

/// The path [entryName] extracts to inside [root], or a [FormatException]
/// when it would end up outside it.
String archiveEntryTarget(String root, String entryName) {
  final target = p.normalize(p.join(root, entryName));
  if (!p.isWithin(root, target) && !p.equals(root, target)) {
    throw FormatException(
        'Refusing to extract "$entryName": it points outside $root.');
  }
  return target;
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
