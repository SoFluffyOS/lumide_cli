import 'dart:io';

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

      await runCheckedProcess('ditto', [
        appBundlePath,
        destination,
      ], failureMessage: 'Failed to copy Lumide into $installDirectory.');

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

    await extractArchive(archivePath, destination);

    if (Platform.isLinux) {
      await _integrateLinuxDesktop(destination);
    }

    return defaultLumideAppPath();
  }

  Future<void> _integrateLinuxDesktop(String installDir) async {
    final desktopFileSource = p.join(installDir, 'io.sofluffy.lumide.desktop');
    if (!File(desktopFileSource).existsSync()) return;

    final applicationsDir = p.join(
      homeDirectoryPath(),
      '.local',
      'share',
      'applications',
    );
    await ensureDirectoryExists(applicationsDir);

    final desktopFileDest = p.join(
      applicationsDir,
      'io.sofluffy.lumide.desktop',
    );
    final content = await File(desktopFileSource).readAsString();

    // Patch paths in .desktop file
    final patchedContent = content
        .replaceAll(RegExp(r'Exec=.*'), 'Exec=$installDir/Lumide %U')
        .replaceAll(RegExp(r'Icon=.*'), 'Icon=$installDir/lumide.png');

    await File(desktopFileDest).writeAsString(patchedContent);

    // Copy icon if exists
    final iconSource = p.join(installDir, 'lumide.png');
    if (File(iconSource).existsSync()) {
      final iconDestDir = p.join(
        homeDirectoryPath(),
        '.local',
        'share',
        'icons',
        'hicolor',
        '512x512',
        'apps',
      );
      await ensureDirectoryExists(iconDestDir);
      await File(
        iconSource,
      ).copy(p.join(iconDestDir, 'io.sofluffy.lumide.png'));
    }

    // Try to update desktop database
    await Process.run('update-desktop-database', [applicationsDir]);
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
