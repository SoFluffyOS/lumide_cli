import 'dart:io';

import 'package:lumide/src/lumide_process_environment.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The Dart that `lumide doctor` checks, as Lumide starts plugins with it.
void main() {
  late Directory temp;
  late String flutterBin; // Has dart.bat, like Flutter's bin folder.
  late String sdkDart; // flutterBin/cache/dart-sdk/bin/dart.exe.

  void touch(String path) => File(path).createSync(recursive: true);

  String launch(String resolved, {String os = 'windows'}) =>
      LumideProcessEnvironment.dartLaunchExecutable(
        resolved,
        operatingSystem: os,
      );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumide_windows_dart_test_');
    flutterBin = p.join(temp.path, 'flutter', 'bin');
    sdkDart = p.join(flutterBin, 'cache', 'dart-sdk', 'bin', 'dart.exe');
    touch(p.join(flutterBin, 'dart.bat'));
  });

  tearDown(() => temp.delete(recursive: true));

  test("Windows: Flutter's dart.bat goes through the dart.exe behind it", () {
    touch(sdkDart);
    expect(launch(p.join(flutterBin, 'dart.bat')), sdkDart);
  });

  test('Windows: the name is matched without case', () {
    touch(sdkDart);
    expect(launch(p.join(flutterBin, 'DART.BAT')), sdkDart);
  });

  test('Windows: dart.bat stays when the SDK cache is missing', () {
    final batch = p.join(flutterBin, 'dart.bat');
    expect(launch(batch), batch);
  });

  test('Windows: a dart.exe is used as is', () {
    final exe = p.join(temp.path, 'dart-sdk', 'bin', 'dart.exe');
    expect(launch(exe), exe);
  });

  test('other platforms: the resolved dart is used as is', () {
    touch(sdkDart);
    final batch = p.join(flutterBin, 'dart.bat');
    expect(launch(batch, os: 'linux'), batch);
    expect(launch(batch, os: 'macos'), batch);
  });
}
