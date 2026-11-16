import 'dart:io';

import 'package:lumide/src/background_tasks.dart';
import 'package:lumide/src/constants.dart';
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

    // For Linux, use the structure from install.sh: ~/.local/opt/lumide
    // For Windows: LOCALAPPDATA/Lumide
    final String destination;
    if (Platform.isLinux) {
      destination = p.join(homeDirectoryPath(), '.local', 'opt', 'lumide');
    } else if (Platform.isWindows) {
      destination = p.join(installDirectory, 'Lumide');
    } else {
      destination = p.join(installDirectory, 'Lumide');
    }

    final destDir = Directory(destination);

    if (await destDir.exists()) {
      if (!force) {
        throw ProcessException(
          'install',
          [destination],
          'Lumide is already installed at $destination. '
              'Re-run with --force to replace it.',
        );
      }
      await destDir.delete(recursive: true);
    }

    await extractArchiveInBackground(archivePath, destination);

    if (Platform.isLinux) {
      await _integrateLinuxDesktop(destination);
    }

    return defaultLumideAppPath();
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

String defaultLumideInstallDirectory() {
  if (Platform.isMacOS) return defaultMacOsInstallDirectory();
  if (Platform.isWindows) return defaultWindowsInstallDirectory();
  return defaultLinuxInstallDirectory();
}

String defaultLumideAppPath() {
  if (Platform.isMacOS) {
    final systemInstall = p.join('/Applications', kLumideAppBundleName);
    if (Directory(systemInstall).existsSync()) {
      return systemInstall;
    }

    final userInstall = p.join(
      homeDirectoryPath(),
      'Applications',
      kLumideAppBundleName,
    );
    if (Directory(userInstall).existsSync()) {
      return userInstall;
    }

    return systemInstall;
  }

  if (Platform.isWindows) {
    return p.join(defaultWindowsInstallDirectory(), 'Lumide', 'Lumide.exe');
  }

  // Linux structure from install.sh
  return p.join(homeDirectoryPath(), '.local', 'opt', 'lumide', 'Lumide');
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
