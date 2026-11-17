import 'dart:io';

import 'package:lumide/src/app_version.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeVersion', () {
    test('drops a leading v and build metadata', () {
      expect(normalizeVersion('v0.25.0'), '0.25.0');
      expect(normalizeVersion(' 0.25.0+12 '), '0.25.0');
      expect(normalizeVersion('0.25.0'), '0.25.0');
    });
  });

  group('compareVersions', () {
    test('compares number by number, not as text', () {
      expect(compareVersions('0.9.0', '0.25.0'), lessThan(0));
      expect(compareVersions('0.26.0', '0.25.9'), greaterThan(0));
      expect(compareVersions('v0.25.0', '0.25.0'), 0);
    });

    test('missing parts count as 0', () {
      expect(compareVersions('0.25', '0.25.0'), 0);
      expect(compareVersions('0.25.0.1', '0.25.0'), greaterThan(0));
    });

    test('is null for versions that are not plain numbers', () {
      expect(compareVersions('0.26.0-beta', '0.25.0'), isNull);
      expect(compareVersions('unknown', '0.25.0'), isNull);
    });
  });

  group('isUpToDate', () {
    test('compares, counts a newer local build as up to date', () {
      expect(isUpToDate('0.25.0', 'v0.25.0'), isTrue);
      expect(isUpToDate('0.25.0', '0.26.0'), isFalse);
      expect(isUpToDate('0.27.0', '0.26.0'), isTrue);
    });

    test('is null when either is unknown', () {
      expect(isUpToDate(null, '0.26.0'), isNull);
      expect(isUpToDate('0.25.0', null), isNull);
    });
  });

  group('describeVersions', () {
    test('up to date / update / offline / unknown', () {
      expect(describeVersions('0.25.0', 'v0.25.0'), '0.25.0, up to date');
      expect(describeVersions('0.25.0', '0.26.0'), '0.25.0, 0.26.0 available');
      expect(describeVersions('0.25.0', null),
          '0.25.0, could not check the latest release');
      expect(describeVersions(null, '0.26.0'),
          'version unknown, latest release 0.26.0');
    });
  });

  test('macOS: reads the bundle version', () async {
    final temp = await Directory.systemTemp.createTemp('lumide_ver_');
    final plist = File('${temp.path}/Lumide.app/Contents/Info.plist')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleShortVersionString</key><string>0.25.0</string>
</dict></plist>''');
    expect(installedLumideVersion(plist.parent.parent.path), '0.25.0');
    await temp.delete(recursive: true);
  }, testOn: 'mac-os');

  group('installedLumideVersion', () {
    test('Windows: reads the version resource of an .exe', () {
      // kernel32.dll is on every Windows and has a version resource
      // (dart.exe does not).
      final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final version =
          installedLumideVersion('$systemRoot\\System32\\kernel32.dll');
      expect(version, matches(RegExp(r'^\d+\.\d+\.\d+')));
    }, testOn: 'windows');

    test('is null for a missing file or one without a version', () async {
      expect(installedLumideVersion(r'C:\nope\Lumide.exe'), isNull);
      final temp = await Directory.systemTemp.createTemp('lumide_ver_');
      final file = File('${temp.path}/Lumide.exe')..writeAsStringSync('x');
      expect(installedLumideVersion(file.path), isNull);
      await temp.delete(recursive: true);
    }, testOn: 'windows');

    test('Linux has no version to read', () {
      expect(installedLumideVersion('/opt/Lumide', operatingSystem: 'linux'),
          isNull);
    });
  });
}
