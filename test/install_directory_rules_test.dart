import 'dart:io';

import 'package:lumide/src/app_installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The folder rules, checked with the Windows layout (`<dir>\Lumide\Lumide.exe`).
void main() {
  const os = 'windows';
  late Directory temp;
  late String tools; // An install directory with Lumide installed in it.
  late String appFolder; // tools\Lumide

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumide_dir_rules_test_');
    tools = p.join(temp.path, 'Tools');
    appFolder = p.join(tools, 'Lumide');
    File(p.join(appFolder, 'Lumide.exe')).createSync(recursive: true);
  });

  tearDown(() => temp.delete(recursive: true));

  group('resolveLumideInstallDirectory', () {
    test("the app's own folder means its install folder", () {
      expect(
          resolveLumideInstallDirectory(appFolder, operatingSystem: os), tools);
    });

    test('the install folder stays as it is', () {
      expect(resolveLumideInstallDirectory(tools, operatingSystem: os), tools);
    });

    test('a "Lumide" folder without Lumide in it stays as it is', () {
      // e.g. a project folder named Lumide: never treated as the app.
      final project = p.join(temp.path, 'Projects', 'Lumide');
      Directory(project).createSync(recursive: true);
      expect(
          resolveLumideInstallDirectory(project, operatingSystem: os), project);
    });

    test('a hand-unzipped app folder with another name stays as it is', () {
      final unzipped = p.join(temp.path, 'Lumide v0.25.0');
      File(p.join(unzipped, 'Lumide.exe')).createSync(recursive: true);
      expect(resolveLumideInstallDirectory(unzipped, operatingSystem: os),
          unzipped);
    });

    test('makes a relative path absolute', () {
      expect(p.isAbsolute(resolveLumideInstallDirectory('apps')), isTrue);
    });
  });

  group('enclosingLumideAppFolder', () {
    test('finds an installed Lumide around the folder', () {
      expect(
        enclosingLumideAppFolder(p.join(appFolder, 'any', 'thing'),
            operatingSystem: os),
        appFolder,
      );
    });

    test('is null for folders outside any installation', () {
      expect(enclosingLumideAppFolder(tools, operatingSystem: os), isNull);
      expect(
          enclosingLumideAppFolder(p.join(temp.path, 'Other', 'x'),
              operatingSystem: os),
          isNull);
    });
  });

  group('unrelatedFolderAtInstallTarget', () {
    test('a Lumide folder that holds something else is reported', () {
      final projects = p.join(temp.path, 'Projects');
      File(p.join(projects, 'Lumide', 'pubspec.yaml'))
          .createSync(recursive: true);
      expect(unrelatedFolderAtInstallTarget(projects, operatingSystem: os),
          p.join(projects, 'Lumide'));
    });

    test('an installed Lumide or no folder at all is fine', () {
      expect(
          unrelatedFolderAtInstallTarget(tools, operatingSystem: os), isNull);
      expect(
          unrelatedFolderAtInstallTarget(p.join(temp.path, 'New'),
              operatingSystem: os),
          isNull);
    });

    test('the old doubled layout counts as an installed Lumide', () {
      final old = p.join(temp.path, 'Old');
      File(p.join(old, 'Lumide', 'Lumide', 'Lumide.exe'))
          .createSync(recursive: true);
      expect(unrelatedFolderAtInstallTarget(old, operatingSystem: os), isNull);
    });
  });

  group('checkLumideInstallDirectory', () {
    test('refuses a folder inside an installation, explaining why', () {
      if (!Platform.isWindows) return; // Uses the platform's own layout.
      expect(
        () => checkLumideInstallDirectory(p.join(appFolder, 'sub')),
        throwsA(isA<ProcessException>().having(
            (e) => e.message, 'message', contains('inside the Lumide'))),
      );
    });

    test('refuses to replace an unrelated folder', () {
      if (!Platform.isWindows) return;
      final projects = p.join(temp.path, 'Projects');
      Directory(p.join(projects, 'Lumide')).createSync(recursive: true);
      expect(
        () => checkLumideInstallDirectory(projects),
        throwsA(isA<ProcessException>().having((e) => e.message, 'message',
            contains('not a Lumide installation'))),
      );
    });

    test('accepts an existing installation and a new folder', () {
      if (!Platform.isWindows) return;
      checkLumideInstallDirectory(tools);
      checkLumideInstallDirectory(p.join(temp.path, 'New'));
    });
  });
}
