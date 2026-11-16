import 'dart:io';

import 'package:lumide/src/app_installer.dart';
import 'package:lumide/src/constants.dart';
import 'package:lumide/src/install_location_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('lumideCliConfigDirectory', () {
    test('Windows uses LOCALAPPDATA', () {
      expect(
        lumideCliConfigDirectory(
          environment: {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
          operatingSystem: 'windows',
        ),
        p.join(r'C:\Users\me\AppData\Local', 'lumide-cli'),
      );
    });

    test('Windows falls back to USERPROFILE\\AppData\\Local', () {
      expect(
        lumideCliConfigDirectory(
          environment: {'USERPROFILE': r'C:\Users\me'},
          operatingSystem: 'windows',
        ),
        p.join(r'C:\Users\me', 'AppData', 'Local', 'lumide-cli'),
      );
    });

    test('macOS uses Application Support', () {
      expect(
        lumideCliConfigDirectory(
          environment: {'HOME': '/Users/me'},
          operatingSystem: 'macos',
        ),
        p.join('/Users/me', 'Library', 'Application Support', 'lumide-cli'),
      );
    });

    test('Linux uses an absolute XDG_CONFIG_HOME', () {
      final xdg = p.join(Directory.systemTemp.path, 'xdg');
      expect(
        lumideCliConfigDirectory(
          environment: {'HOME': '/home/me', 'XDG_CONFIG_HOME': xdg},
          operatingSystem: 'linux',
        ),
        p.join(xdg, 'lumide-cli'),
      );
    });

    test('Linux ignores a relative XDG_CONFIG_HOME', () {
      expect(
        lumideCliConfigDirectory(
          environment: {'HOME': '/home/me', 'XDG_CONFIG_HOME': 'relative'},
          operatingSystem: 'linux',
        ),
        p.join('/home/me', '.config', 'lumide-cli'),
      );
    });
  });

  group('saved install directory', () {
    late Directory temp;
    late Map<String, String> env;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('lumide_cli_test_');
      // Point every per-OS config location at the temp folder.
      env = {
        'LOCALAPPDATA': temp.path,
        'USERPROFILE': temp.path,
        'HOME': temp.path,
        'XDG_CONFIG_HOME': temp.path,
      };
    });

    tearDown(() => temp.delete(recursive: true));

    File configFile() =>
        File(p.join(lumideCliConfigDirectory(environment: env), 'config.json'));

    test('is null when nothing was saved', () {
      expect(savedLumideInstallDirectory(env), isNull);
    });

    test('round-trips through save and read', () async {
      await saveLumideInstallDirectory(r'D:\Tools', env);
      expect(savedLumideInstallDirectory(env), r'D:\Tools');
      expect(File('${configFile().path}.tmp').existsSync(), isFalse);
    });

    test('saving null forgets it and keeps other settings', () async {
      await configFile().create(recursive: true);
      await configFile()
          .writeAsString('{"installDirectory": "D:/Tools", "other": 1}');
      await saveLumideInstallDirectory(null, env);
      expect(savedLumideInstallDirectory(env), isNull);
      expect(await configFile().readAsString(), contains('"other": 1'));
    });

    test('a corrupt config file is ignored instead of crashing', () async {
      await configFile().create(recursive: true);
      await configFile().writeAsString('{not json');
      expect(savedLumideInstallDirectory(env), isNull);
      await saveLumideInstallDirectory('/opt/apps', env);
      expect(savedLumideInstallDirectory(env), '/opt/apps');
    });

    test('LUMIDE_INSTALL_DIR beats the saved directory', () async {
      await saveLumideInstallDirectory('/saved', env);
      final fromEnv = p.join(temp.path, 'from-env');
      final withVar = {...env, kLumideInstallDirEnvVar: fromEnv};
      expect(defaultLumideInstallDirectory(withVar), fromEnv);
    });

    test('the saved directory beats the platform default', () async {
      await saveLumideInstallDirectory('/saved', env);
      expect(defaultLumideInstallDirectory(env), '/saved');
      expect(defaultLumideAppPath(env),
          lumideAppPathForInstallDirectory('/saved'));
    });

    test('nothing configured falls back to the platform default', () {
      expect(configuredLumideInstallDirectory(env), isNull);
      expect(defaultLumideInstallDirectory(env),
          platformDefaultLumideInstallDirectory());
    });
  });
}
