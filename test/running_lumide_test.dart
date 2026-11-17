import 'dart:io';

import 'package:lumide/src/app_installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Detecting a Lumide that runs from the folder `lumide install` replaces.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumide_running_test_');
  });

  tearDown(() async {
    // Windows may hold an executable for a moment after its process ends.
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        await temp.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
  });

  group('firstExecutableInside', () {
    late String folder;

    setUp(() {
      folder = p.join(temp.path, 'Tools', 'Lumide');
      Directory(folder).createSync(recursive: true);
    });

    test('finds a process running from the folder', () {
      final app = p.join(folder, 'Lumide');
      expect(firstExecutableInside(folder, ['/usr/bin/ssh', app]), app);
    });

    test(
        'ignores processes elsewhere, including a folder with the same '
        'prefix', () {
      expect(
        firstExecutableInside(folder, [
          p.join(temp.path, 'Tools', 'Lumide2', 'Lumide'),
          p.join(temp.path, 'Tools', 'Lumide.new', 'Lumide'),
          p.join(temp.path, 'Tools', 'other'),
        ]),
        isNull,
      );
    });

    test('also matches the real path of the folder', () {
      final real = Directory(folder).resolveSymbolicLinksSync();
      final app = p.join(real, 'Lumide');
      expect(firstExecutableInside(folder, [app]), app);
    });

    test('is null when the folder does not exist', () {
      expect(
        firstExecutableInside(p.join(temp.path, 'Missing'),
            [p.join(temp.path, 'Missing', 'Lumide')]),
        isNull,
      );
    });
  });

  /// Starts [program] as the Lumide executable at [app], checks that it is
  /// found while it runs and not after it ends.
  Future<void> expectFoundWhileRunning(
    String installDirectory,
    String app,
    String program,
    List<String> arguments,
  ) async {
    Directory(p.dirname(app)).createSync(recursive: true);
    File(program).copySync(app);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', app]);
    }
    expect(runningLumideApp(installDirectory), isNull);

    final process = await Process.start(app, arguments);
    try {
      // Give the process a moment to show up in the process list.
      String? running;
      for (var attempt = 0; attempt < 10 && running == null; attempt++) {
        running = runningLumideApp(installDirectory);
        if (running == null) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      expect(running, isNotNull);
      expect(p.basename(running!), p.basename(app));
    } finally {
      process.kill();
      await process.exitCode;
    }

    String? running = app;
    for (var attempt = 0; attempt < 10 && running != null; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      running = runningLumideApp(installDirectory);
    }
    expect(running, isNull);
  }

  test('Windows: a running Lumide.exe is found', () async {
    final installDirectory = p.join(temp.path, 'Tools');
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    await expectFoundWhileRunning(
      installDirectory,
      p.join(installDirectory, 'Lumide', 'Lumide.exe'),
      p.join(systemRoot, 'System32', 'PING.EXE'),
      ['-n', '30', '127.0.0.1'],
    );
  }, testOn: 'windows');

  test('Linux: a running Lumide is found through /proc', () async {
    final installDirectory = p.join(temp.path, 'Tools');
    await expectFoundWhileRunning(
      installDirectory,
      p.join(installDirectory, 'lumide', 'Lumide'),
      '/bin/sleep',
      ['30'],
    );
  }, testOn: 'linux');

  test('macOS: a running Lumide.app is found through ps', () async {
    final installDirectory = p.join(temp.path, 'Applications');
    await expectFoundWhileRunning(
      installDirectory,
      p.join(installDirectory, 'Lumide.app', 'Contents', 'MacOS', 'Lumide'),
      '/bin/sleep',
      ['30'],
    );
  }, testOn: 'mac-os');

  test('nothing is found when the folder holds no Lumide', () {
    expect(runningLumideApp(p.join(temp.path, 'Empty')), isNull);
  });
}
