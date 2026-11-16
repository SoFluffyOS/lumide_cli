import 'dart:io';

import 'package:lumide/src/lumide_process_environment.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// How `lumide doctor` decides whether Lumide.exe can start a bare `dart`
/// on Windows.
void main() {
  late Directory temp;
  late String flutterBin; // Has dart.bat, like Flutter's bin folder.
  late String sdkBin; // flutterBin\cache\dart-sdk\bin with dart.exe.

  void touch(String path) => File(path).createSync(recursive: true);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumide_windows_dart_test_');
    flutterBin = p.join(temp.path, 'flutter', 'bin');
    sdkBin = p.join(flutterBin, 'cache', 'dart-sdk', 'bin');
    touch(p.join(flutterBin, 'dart.bat'));
    touch(p.join(sdkBin, 'dart.exe'));
  });

  tearDown(() => temp.delete(recursive: true));

  test('only Flutter\'s dart.bat in PATH: no exe, and the folder to add', () {
    final result =
        LumideProcessEnvironment.windowsDart(pathEntries: [flutterBin]);
    expect(result.exe, isNull);
    expect(result.batch, p.join(flutterBin, 'dart.bat'));
    expect(result.sdkBin, sdkBin);
  });

  test('a dart.exe anywhere in PATH is used, even after dart.bat', () {
    final result =
        LumideProcessEnvironment.windowsDart(pathEntries: [flutterBin, sdkBin]);
    expect(result.exe, p.join(sdkBin, 'dart.exe'));
    expect(result.batch, isNull);
  });

  test("dart.exe in Lumide's own folder comes first", () {
    final appFolder = p.join(temp.path, 'Lumide');
    touch(p.join(appFolder, 'dart.exe'));
    final result = LumideProcessEnvironment.windowsDart(
        appFolder: appFolder, pathEntries: [sdkBin]);
    expect(result.exe, p.join(appFolder, 'dart.exe'));
  });

  test('a dart.bat without a Dart SDK behind it gives no folder to add', () {
    final other = p.join(temp.path, 'tools');
    touch(p.join(other, 'dart.cmd'));
    final result = LumideProcessEnvironment.windowsDart(pathEntries: [other]);
    expect(result.exe, isNull);
    expect(result.batch, p.join(other, 'dart.cmd'));
    expect(result.sdkBin, isNull);
  });

  test('nothing in PATH', () {
    final result = LumideProcessEnvironment.windowsDart(
        pathEntries: ['', '  ', p.join(temp.path, 'empty')]);
    expect(result.exe, isNull);
    expect(result.batch, isNull);
    expect(result.sdkBin, isNull);
  });

  group('launchEnvironmentWithDart (the PATH Lumide is started with)', () {
    test("appends Flutter's Dart SDK when PATH only has dart.bat", () {
      final other = p.join(temp.path, 'other');
      final env = {'Path': '$other;$flutterBin', 'HOME': 'x'};
      expect(LumideProcessEnvironment.launchEnvironmentWithDart(env),
          {'Path': '$other;$flutterBin;$sdkBin'});
    });

    test('keeps the name of the PATH variable (case-insensitive on Windows)',
        () {
      expect(
        LumideProcessEnvironment.launchEnvironmentWithDart(
            {'PATH': flutterBin}),
        {'PATH': '$flutterBin;$sdkBin'},
      );
    });

    test('changes nothing when Lumide already finds a dart.exe', () {
      expect(
        LumideProcessEnvironment.launchEnvironmentWithDart(
            {'Path': '$flutterBin;$sdkBin'}),
        isNull,
      );
      final appFolder = p.join(temp.path, 'Lumide');
      touch(p.join(appFolder, 'dart.exe'));
      expect(
        LumideProcessEnvironment.launchEnvironmentWithDart({'Path': flutterBin},
            appFolder: appFolder),
        isNull,
      );
    });

    test('changes nothing when there is no Dart SDK to add', () {
      final other = p.join(temp.path, 'tools');
      touch(p.join(other, 'dart.cmd'));
      expect(
          LumideProcessEnvironment.launchEnvironmentWithDart({'Path': other}),
          isNull);
      expect(LumideProcessEnvironment.launchEnvironmentWithDart({}), isNull);
    });
  });
}
