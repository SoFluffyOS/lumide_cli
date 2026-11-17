import 'dart:io';

import 'package:lumide/src/background_tasks.dart';
import 'package:lumide/src/constants.dart';
import 'package:lumide/src/install_location_config.dart';
import 'package:lumide/src/io_helpers.dart';
import 'package:path/path.dart' as p;

class AppInstaller {
  const AppInstaller();

  Future<String> install({
    required String packagePath,
    required String installDirectory,
    required bool force,
  }) async {
    if (Platform.isMacOS && packagePath.endsWith('.dmg')) {
      return _installMacOsDmg(packagePath, installDirectory, force);
    } else {
      return _installArchive(packagePath, installDirectory, force);
    }
  }

  Future<String> _installMacOsDmg(
    String dmgPath,
    String installDirectory,
    bool force,
  ) async {
    await ensureDirectoryExists(installDirectory);

    final mountPoint = await attachDiskImage(dmgPath);
    try {
      final appBundlePath = await findAppBundle(mountPoint);
      final destination = p.join(installDirectory, p.basename(appBundlePath));

      final destinationDirectory = Directory(destination);
      if (await destinationDirectory.exists()) {
        if (!force) {
          throw ProcessException(
            'install',
            [destination],
            'Lumide is already installed at $destination. '
                'Re-run with --force to replace it.',
          );
        }
        await destinationDirectory.delete(recursive: true);
      }

      await runCheckedProcess(
          'ditto',
          [
            appBundlePath,
            destination,
          ],
          failureMessage: 'Failed to copy Lumide into $installDirectory.');

      return destination;
    } finally {
      await Process.run('hdiutil', ['detach', '-force', mountPoint]);
    }
  }

  Future<String> _installArchive(
    String archivePath,
    String installDirectory,
    bool force,
  ) async {
    await ensureDirectoryExists(installDirectory);

    final destination = lumideInstallTarget(installDirectory);
    checkLumideInstallDirectory(installDirectory);
    final destDir = Directory(destination);

    if (!force && await destDir.exists()) {
      throw ProcessException(
        'install',
        [destination],
        'Lumide is already installed at $destination. '
            'Re-run with --force to replace it.',
      );
    }

    await replaceDirectory(
      destination,
      (staging) => extractArchiveInBackground(archivePath, staging),
    );

    if (Platform.isLinux) {
      await _integrateLinuxDesktop(destination);
    }

    return lumideAppPathForInstallDirectory(installDirectory);
  }

  /// Adds Lumide to the app menu: copies its .desktop file and icon into
  /// the user's data folder ($XDG_DATA_HOME, by default ~/.local/share).
  Future<void> _integrateLinuxDesktop(String installDir) async {
    // Current archives keep these under share/; older ones at the top.
    final desktopFileSource = _firstExistingFile([
      p.join(installDir, 'share', 'applications', '$kLinuxAppId.desktop'),
      p.join(installDir, '$kLinuxAppId.desktop'),
    ]);
    if (desktopFileSource == null) return;
    final iconSource = _firstExistingFile([
      p.join(installDir, 'share', 'icons', 'hicolor', '512x512', 'apps',
          '$kLinuxAppId.png'),
      p.join(installDir, 'lumide.png'),
    ]);

    final dataHome = linuxDataHome();
    final iconThemeDir = p.join(dataHome, 'icons', 'hicolor');
    if (iconSource != null) {
      final iconDestDir = p.join(iconThemeDir, '512x512', 'apps');
      await ensureDirectoryExists(iconDestDir);
      await File(iconSource).copy(p.join(iconDestDir, '$kLinuxAppId.png'));
    }

    final applicationsDir = p.join(dataHome, 'applications');
    await ensureDirectoryExists(applicationsDir);
    final content = await File(desktopFileSource).readAsString();
    await File(p.join(applicationsDir, '$kLinuxAppId.desktop')).writeAsString(
      patchLinuxDesktopEntry(
        content,
        executable: p.join(installDir, 'Lumide'),
        iconName: iconSource == null ? null : kLinuxAppId,
      ),
    );

    // Refresh the caches if the tools are installed. Desktops also pick up
    // the new files without them, so failures are ignored.
    await _runIgnoringErrors('update-desktop-database', [applicationsDir]);
    if (iconSource != null) {
      await _runIgnoringErrors(
          'gtk-update-icon-cache', ['-f', '-t', iconThemeDir]);
    }
  }

  static String? _firstExistingFile(List<String> paths) {
    for (final path in paths) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  static Future<void> _runIgnoringErrors(
    String executable,
    List<String> arguments,
  ) async {
    try {
      await Process.run(executable, arguments);
    } on ProcessException {
      // Not installed.
    }
  }

  Future<String> attachDiskImage(String dmgPath) async {
    final result = await Process.run('hdiutil', [
      'attach',
      '-nobrowse',
      '-plist',
      dmgPath,
    ]);

    if (result.exitCode != 0) {
      throw ProcessException(
        'hdiutil',
        ['attach', '-nobrowse', '-plist', dmgPath],
        'Failed to mount DMG: ${result.stderr}',
        result.exitCode,
      );
    }

    final mountPoint = parseMountPoint(result.stdout.toString());
    if (mountPoint == null || mountPoint.isEmpty) {
      throw const FormatException('Could not determine DMG mount point.');
    }
    return mountPoint;
  }

  Future<String> findAppBundle(String mountPoint) async {
    await for (final entity in Directory(mountPoint).list()) {
      if (entity is Directory && p.extension(entity.path) == '.app') {
        return entity.path;
      }
    }

    throw const FileSystemException('No .app bundle found inside mounted DMG.');
  }
}

String? parseMountPoint(String plistOutput) {
  final match = RegExp(
    r'<key>mount-point</key>\s*<string>(.*?)</string>',
    dotAll: true,
  ).firstMatch(plistOutput);
  return match?.group(1);
}

/// Replaces the folder [target] with one that [fill] writes into a staging
/// folder next to it. The current folder is only swapped out once [fill]
/// succeeds, so a failed or interrupted install leaves it working; if the
/// swap itself fails (e.g. Lumide is running on Windows), it is put back.
Future<void> replaceDirectory(
  String target,
  Future<void> Function(String staging) fill,
) async {
  final staging = Directory('$target.new');
  final previous = Directory('$target.old');
  await _deleteIfExists(staging);
  await _deleteIfExists(previous);

  try {
    await fill(staging.path);
    await _swapDirectory(staging, Directory(target), previous);
  } finally {
    await _deleteIfExists(staging);
  }
  await _deleteIfExists(previous);
}

Future<void> _swapDirectory(
  Directory replacement,
  Directory target,
  Directory backup,
) async {
  final hasTarget = await target.exists();
  if (hasTarget) await target.rename(backup.path);
  try {
    await replacement.rename(target.path);
  } catch (_) {
    if (hasTarget) await backup.rename(target.path);
    rethrow;
  }
}

/// Best effort: a leftover folder must not fail the install.
Future<void> _deleteIfExists(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } on FileSystemException {
    // Still in use; the next install tries again.
  }
}

/// The install directory set through [kLumideInstallDirEnvVar], or `null`.
String? lumideInstallDirectoryOverride([Map<String, String>? environment]) {
  final value = (environment ?? Platform.environment)[kLumideInstallDirEnvVar];
  if (value == null || value.trim().isEmpty) return null;
  return resolveLumideInstallDirectory(value.trim());
}

/// [kLumideInstallDirEnvVar], else the folder saved by
/// `lumide install --install-dir`, else `null`.
String? configuredLumideInstallDirectory([Map<String, String>? environment]) {
  return lumideInstallDirectoryOverride(environment) ??
      savedLumideInstallDirectory(environment);
}

/// The install directory when nothing is configured.
String platformDefaultLumideInstallDirectory() {
  if (Platform.isMacOS) return defaultMacOsInstallDirectory();
  if (Platform.isWindows) return defaultWindowsInstallDirectory();
  return defaultLinuxInstallDirectory();
}

/// The configured install directory, else the platform default.
String defaultLumideInstallDirectory([Map<String, String>? environment]) {
  return configuredLumideInstallDirectory(environment) ??
      platformDefaultLumideInstallDirectory();
}

/// [desktopEntry] with every `Exec=` line (including actions such as
/// "New Window") running [executable], keeping each line's arguments, and
/// `Icon=` set to [iconName] when given.
String patchLinuxDesktopEntry(
  String desktopEntry, {
  required String executable,
  String? iconName,
}) {
  var patched = desktopEntry.replaceAllMapped(
    RegExp(r'^Exec=("(?:[^"\\]|\\.)*"|\S*)(.*)$', multiLine: true),
    (match) => 'Exec=${quoteDesktopExecArgument(executable)}${match[2]}',
  );
  if (iconName != null) {
    patched = patched.replaceAll(
      RegExp(r'^Icon=.*$', multiLine: true),
      'Icon=$iconName',
    );
  }
  return patched;
}

/// [argument] quoted for an `Exec=` line, as the Desktop Entry spec
/// requires (a literal backslash takes four, because the file's own string
/// escaping applies first).
String quoteDesktopExecArgument(String argument) {
  final escaped = argument
      .replaceAll(r'\', r'\\\\')
      .replaceAll('"', r'\"')
      .replaceAll('`', r'\`')
      .replaceAll(r'$', r'\$');
  return '"$escaped"';
}

/// Whether to offer using the Lumide already in [installDirectory] from now
/// on: not when [kLumideInstallDirEnvVar] is set (it decides anyway) or
/// when other commands already use that folder.
bool shouldOfferToUseExistingInstall(
  String installDirectory, [
  Map<String, String>? environment,
]) {
  return lumideInstallDirectoryOverride(environment) == null &&
      !p.equals(defaultLumideInstallDirectory(environment), installDirectory);
}

/// Where the archive is extracted on Linux for [installDirectory].
///
/// The default location keeps the structure from install.sh
/// (`~/.local/opt/lumide`); any other directory gets a `lumide` subfolder.
String linuxInstallDestination(String installDirectory) {
  if (p.equals(installDirectory, defaultLinuxInstallDirectory())) {
    return p.join(homeDirectoryPath(), '.local', 'opt', 'lumide');
  }
  return p.join(installDirectory, 'lumide');
}

/// The folder `lumide install` writes the app to (and replaces on upgrade)
/// for [installDirectory].
String lumideInstallTarget(String installDirectory, {String? operatingSystem}) {
  return switch (operatingSystem ?? Platform.operatingSystem) {
    'macos' => p.join(installDirectory, kLumideAppBundleName),
    'windows' => p.join(installDirectory, 'Lumide'),
    _ => linuxInstallDestination(installDirectory),
  };
}

/// Where Lumide can be for [installDirectory], in the order they are
/// checked: where `lumide install` puts it, the doubled `Lumide/Lumide`
/// layout older CLI versions created from the 0.25 archives, and (Windows,
/// Linux) [installDirectory] being the app's own folder, e.g. an archive
/// unzipped by hand. A fixed list rather than a search, so a stray old
/// copy is never picked up.
List<String> lumideAppCandidatesForInstallDirectory(
  String installDirectory, {
  String? operatingSystem,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final target = lumideInstallTarget(installDirectory, operatingSystem: os);
  return switch (os) {
    'macos' => [target],
    'windows' => [
        p.join(target, 'Lumide.exe'),
        p.join(target, 'Lumide', 'Lumide.exe'),
        p.join(installDirectory, 'Lumide.exe'),
      ],
    _ => [
        p.join(target, 'Lumide'),
        p.join(target, 'Lumide', 'Lumide'),
        p.join(installDirectory, 'Lumide'),
        p.join(installDirectory, 'Lumide', 'Lumide'),
      ],
  };
}

/// Whether installing into [installDirectory] replaces [appPath], i.e. it
/// lies in [lumideInstallTarget]. A copy elsewhere is left alone.
bool installReplaces(
  String installDirectory,
  String appPath, {
  String? operatingSystem,
}) {
  final target =
      lumideInstallTarget(installDirectory, operatingSystem: operatingSystem);
  return p.equals(target, appPath) || p.isWithin(target, appPath);
}

/// The Lumide program running from [lumideInstallTarget] of
/// [installDirectory], or `null`. Installing replaces that folder: on
/// Windows the swap fails while it runs, and on macOS and Linux it succeeds
/// but the running app loads the new version's files until it restarts.
///
/// - Windows: a running program's .exe cannot be opened for writing
///   (ERROR_SHARING_VIOLATION).
/// - Linux: the `/proc/<pid>/exe` link of every process.
/// - macOS: the executable path of every process, from `ps -axo comm=`.
String? runningLumideApp(String installDirectory) {
  final target = lumideInstallTarget(installDirectory);
  return switch (Platform.operatingSystem) {
    'windows' => _runningWindowsApp(installDirectory),
    'linux' => firstExecutableInside(target, _linuxProcessExecutables()),
    'macos' => firstExecutableInside(target, _macOsProcessExecutables()),
    _ => null,
  };
}

/// The first of [executables] that lies inside [folder], or `null`. Both
/// the folder as given and its real path count, since processes report
/// either (macOS `ps` shows the path a program was started with, Linux
/// `/proc` the real one).
String? firstExecutableInside(String folder, Iterable<String> executables) {
  if (!Directory(folder).existsSync()) return null;
  final roots = {
    p.normalize(p.absolute(folder)),
    Directory(folder).resolveSymbolicLinksSync(),
  };
  for (final executable in executables) {
    if (roots.any((root) => p.isWithin(root, executable))) return executable;
  }
  return null;
}

String? _runningWindowsApp(String installDirectory) {
  const sharingViolation = 32;
  final apps = lumideAppCandidatesForInstallDirectory(installDirectory)
      .where((path) => installReplaces(installDirectory, path));
  for (final path in apps) {
    if (!File(path).existsSync()) continue;
    try {
      File(path).openSync(mode: FileMode.append).closeSync();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == sharingViolation) return path;
    }
  }
  return null;
}

/// The executables of the running processes this user can see.
Iterable<String> _linuxProcessExecutables() sync* {
  final List<FileSystemEntity> entries;
  try {
    entries = Directory('/proc').listSync();
  } on FileSystemException {
    return;
  }
  for (final entry in entries) {
    if (int.tryParse(p.basename(entry.path)) == null) continue;
    try {
      // A replaced or deleted executable reads as "<path> (deleted)".
      final target = Link(p.join(entry.path, 'exe')).targetSync();
      yield target.endsWith(' (deleted)')
          ? target.substring(0, target.length - ' (deleted)'.length)
          : target;
    } on FileSystemException {
      // Another user's process, or one that has just ended.
    }
  }
}

/// The executable paths of the running processes.
List<String> _macOsProcessExecutables() {
  try {
    final result = Process.runSync('ps', ['-axo', 'comm=']);
    if (result.exitCode != 0) return const [];
    return (result.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('/'))
        .toList();
  } on ProcessException {
    return const [];
  }
}

/// Whether [lumideInstallTarget] of [installDirectory] holds an installed
/// Lumide (in either layout), so `lumide install` may replace it.
bool hasManagedLumideInstall(
  String installDirectory, {
  String? operatingSystem,
}) {
  return lumideAppCandidatesForInstallDirectory(installDirectory,
          operatingSystem: operatingSystem)
      .where((path) => installReplaces(installDirectory, path,
          operatingSystem: operatingSystem))
      .any((path) => isLumideApp(path, operatingSystem: operatingSystem));
}

/// Whether [folder] is the app folder of an installed Lumide, i.e. the
/// [lumideInstallTarget] of its parent with Lumide in it.
bool _isLumideAppFolder(String folder, {String? operatingSystem}) {
  final parent = p.dirname(folder);
  return !p.equals(parent, folder) &&
      p.equals(lumideInstallTarget(parent, operatingSystem: operatingSystem),
          folder) &&
      hasManagedLumideInstall(parent, operatingSystem: operatingSystem);
}

/// [installDirectory] as an absolute path, or its parent when it is the app
/// folder of an installed Lumide, so `D:\Tools` and `D:\Tools\Lumide` name
/// the same installation.
String resolveLumideInstallDirectory(
  String installDirectory, {
  String? operatingSystem,
}) {
  final directory = p.normalize(p.absolute(installDirectory));
  return _isLumideAppFolder(directory, operatingSystem: operatingSystem)
      ? p.dirname(directory)
      : directory;
}

/// The app folder of an installed Lumide that [installDirectory] lies
/// inside, or `null`. Installing there is unsafe: upgrading that Lumide
/// replaces its whole folder.
String? enclosingLumideAppFolder(
  String installDirectory, {
  String? operatingSystem,
}) {
  var folder = p.normalize(p.absolute(installDirectory));
  while (true) {
    final parent = p.dirname(folder);
    if (p.equals(parent, folder)) return null;
    folder = parent;
    if (_isLumideAppFolder(folder, operatingSystem: operatingSystem)) {
      return folder;
    }
  }
}

/// Throws a [ProcessException] explaining why `lumide install` must not
/// write to [installDirectory]: it lies inside an installed Lumide, or its
/// [lumideInstallTarget] is an unrelated folder that would be replaced.
void checkLumideInstallDirectory(String installDirectory) {
  final enclosing = enclosingLumideAppFolder(installDirectory);
  if (enclosing != null) {
    throw ProcessException(
      'install',
      [installDirectory],
      '$installDirectory is inside the Lumide installation at $enclosing, '
          'which is replaced when Lumide is upgraded. Choose a folder '
          'outside it.',
    );
  }
  final unrelated = unrelatedFolderAtInstallTarget(installDirectory);
  if (unrelated != null) {
    throw ProcessException(
      'install',
      [installDirectory],
      '$unrelated already exists and is not a Lumide installation, so it '
          'was left untouched. Choose another --install-dir, or move that '
          'folder.',
    );
  }
}

/// [lumideInstallTarget] of [installDirectory] when it exists but holds no
/// Lumide, or `null`. `lumide install` replaces that folder, so it must not
/// touch one that is something else.
String? unrelatedFolderAtInstallTarget(
  String installDirectory, {
  String? operatingSystem,
}) {
  final target =
      lumideInstallTarget(installDirectory, operatingSystem: operatingSystem);
  if (FileSystemEntity.typeSync(target) == FileSystemEntityType.notFound) {
    return null;
  }
  return hasManagedLumideInstall(installDirectory,
          operatingSystem: operatingSystem)
      ? null
      : target;
}

/// Whether [path] is a Lumide app: an app bundle (a folder) on macOS, an
/// executable file elsewhere. A folder named `Lumide` on Linux is not.
bool isLumideApp(String path, {String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final type = FileSystemEntity.typeSync(path);
  return os == 'macos'
      ? type == FileSystemEntityType.directory
      : type == FileSystemEntityType.file;
}

/// The first of [paths] that is a Lumide app, else the first one.
String _firstAppOrFirst(List<String> paths, {String? operatingSystem}) {
  return paths.firstWhere(
    (path) => isLumideApp(path, operatingSystem: operatingSystem),
    orElse: () => paths.first,
  );
}

/// The Lumide app for [installDirectory]: the first existing candidate, or
/// where `lumide install` would put it.
String lumideAppPathForInstallDirectory(
  String installDirectory, {
  String? operatingSystem,
}) {
  return _firstAppOrFirst(
    lumideAppCandidatesForInstallDirectory(installDirectory,
        operatingSystem: operatingSystem),
    operatingSystem: operatingSystem,
  );
}

/// Every place checked for Lumide when [installDirectory] is used. For the
/// default folder on macOS that includes `~/Applications`, as before.
List<String> lumideAppSearchPathsFor(String installDirectory) {
  return [
    ...lumideAppCandidatesForInstallDirectory(installDirectory),
    if (Platform.isMacOS &&
        p.equals(installDirectory, platformDefaultLumideInstallDirectory()))
      p.join(homeDirectoryPath(), 'Applications', kLumideAppBundleName),
  ];
}

/// Every place checked for the installed Lumide, in order.
List<String> lumideAppSearchPaths([Map<String, String>? environment]) {
  return lumideAppSearchPathsFor(defaultLumideInstallDirectory(environment));
}

/// The installed Lumide: the first of [lumideAppSearchPaths] that exists,
/// or where `lumide install` would put it.
String defaultLumideAppPath([Map<String, String>? environment]) {
  return _firstAppOrFirst(lumideAppSearchPaths(environment));
}
