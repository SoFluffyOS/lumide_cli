import 'dart:io';

import 'package:lumide/src/app_installer.dart';
import 'package:lumide/src/constants.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final customDir = p.join(Directory.systemTemp.path, 'lumide-custom');

  group('lumideInstallDirectoryOverride', () {
    test('is null when the variable is not set', () {
      expect(lumideInstallDirectoryOverride({}), isNull);
    });

    test('is null when the variable is empty or blank', () {
      expect(lumideInstallDirectoryOverride({kLumideInstallDirEnvVar: ''}),
          isNull);
      expect(lumideInstallDirectoryOverride({kLumideInstallDirEnvVar: '   '}),
          isNull);
    });

    test('returns the trimmed folder when set', () {
      expect(
        lumideInstallDirectoryOverride(
            {kLumideInstallDirEnvVar: '  $customDir  '}),
        customDir,
      );
    });
  });

  group('LUMIDE_INSTALL_DIR override', () {
    final env = {kLumideInstallDirEnvVar: customDir};

    test('is used as the default install directory', () {
      expect(defaultLumideInstallDirectory(env), customDir);
    });

    test('is used to find the installed app', () {
      expect(
        defaultLumideAppPath(env),
        lumideAppPathForInstallDirectory(customDir),
      );
    });
  });

  group('lumideAppPathForInstallDirectory, nothing installed', () {
    test('Windows: <dir>/Lumide/Lumide.exe', () {
      expect(
        lumideAppPathForInstallDirectory(customDir, operatingSystem: 'windows'),
        p.join(customDir, 'Lumide', 'Lumide.exe'),
      );
    });

    test('macOS: <dir>/Lumide.app', () {
      expect(
        lumideAppPathForInstallDirectory(customDir, operatingSystem: 'macos'),
        p.join(customDir, kLumideAppBundleName),
      );
    });

    test('Linux: custom folder gets a lumide subfolder', () {
      expect(
        lumideAppPathForInstallDirectory(customDir, operatingSystem: 'linux'),
        p.join(customDir, 'lumide', 'Lumide'),
      );
    });
  });

  group('lumideAppCandidatesForInstallDirectory', () {
    test('Windows: install layout, old doubled layout, the app folder', () {
      expect(
        lumideAppCandidatesForInstallDirectory(customDir,
            operatingSystem: 'windows'),
        [
          p.join(customDir, 'Lumide', 'Lumide.exe'),
          p.join(customDir, 'Lumide', 'Lumide', 'Lumide.exe'),
          p.join(customDir, 'Lumide.exe'),
        ],
      );
    });

    test('macOS: only the bundle', () {
      expect(
        lumideAppCandidatesForInstallDirectory(customDir,
            operatingSystem: 'macos'),
        [p.join(customDir, kLumideAppBundleName)],
      );
    });

    test('Linux: install layout, old doubled layout, the app folder', () {
      expect(
        lumideAppCandidatesForInstallDirectory(customDir,
            operatingSystem: 'linux'),
        [
          p.join(customDir, 'lumide', 'Lumide'),
          p.join(customDir, 'lumide', 'Lumide', 'Lumide'),
          p.join(customDir, 'Lumide'),
          p.join(customDir, 'Lumide', 'Lumide'),
        ],
      );
    });

    test('the default folder is checked the same way (old installs there)', () {
      // An install made by CLI 1.1.1 from the 0.25 archives sits at
      // %LOCALAPPDATA%\Lumide\Lumide\Lumide.exe.
      expect(
        lumideAppSearchPaths({}),
        containsAll(lumideAppCandidatesForInstallDirectory(
            platformDefaultLumideInstallDirectory())),
      );
    });
  });

  group('installReplaces', () {
    test('true for the app the installer manages, false for one beside it', () {
      if (!Platform.isWindows) return;
      expect(
          installReplaces(customDir, p.join(customDir, 'Lumide', 'Lumide.exe')),
          isTrue);
      expect(
          installReplaces(
              customDir, p.join(customDir, 'Lumide', 'Lumide', 'Lumide.exe')),
          isTrue);
      expect(
          installReplaces(customDir, p.join(customDir, 'Lumide.exe')), isFalse);
    });
  });

  group('finds an existing app', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('lumide_find_app_test_');
    });

    tearDown(() => temp.delete(recursive: true));

    void createFile(List<String> parts) {
      File(p.joinAll([temp.path, ...parts])).createSync(recursive: true);
    }

    String find(String os) =>
        lumideAppPathForInstallDirectory(temp.path, operatingSystem: os);

    test('Windows: an app folder unzipped by hand (<dir>/Lumide.exe)', () {
      createFile(['Lumide.exe']);
      expect(find('windows'), p.join(temp.path, 'Lumide.exe'));
    });

    test('Windows: the doubled layout from older CLI versions', () {
      createFile(['Lumide', 'Lumide', 'Lumide.exe']);
      expect(
          find('windows'), p.join(temp.path, 'Lumide', 'Lumide', 'Lumide.exe'));
    });

    test('Windows: the install layout wins when several exist', () {
      createFile(['Lumide.exe']);
      createFile(['Lumide', 'Lumide.exe']);
      expect(find('windows'), p.join(temp.path, 'Lumide', 'Lumide.exe'));
    });

    test('Linux: a folder named Lumide is not mistaken for the app', () {
      // <dir>/Lumide is a folder here; the binary is inside it.
      createFile(['Lumide', 'Lumide']);
      // p.equals: on Windows (case-insensitive) the first candidate,
      // <dir>/lumide/Lumide, is this same file.
      expect(p.equals(find('linux'), p.join(temp.path, 'Lumide', 'Lumide')),
          isTrue);
    });

    test('macOS: the bundle is a folder', () {
      Directory(p.join(temp.path, kLumideAppBundleName))
          .createSync(recursive: true);
      expect(find('macos'), p.join(temp.path, kLumideAppBundleName));
    });

    test('LUMIDE_INSTALL_DIR pointing at the app folder works', () {
      createFile(['Lumide.exe']);
      expect(lumideAppSearchPaths({kLumideInstallDirEnvVar: temp.path}),
          lumideAppCandidatesForInstallDirectory(temp.path));
      if (Platform.isWindows) {
        expect(defaultLumideAppPath({kLumideInstallDirEnvVar: temp.path}),
            p.join(temp.path, 'Lumide.exe'));
      }
    });
  });
}
