import 'dart:io';

import 'package:lumide/src/commands/launch_command.dart';
import 'package:lumide/src/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String app;
  late String api;
  late String workspaceFile;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lumide-cli-');
    final resolved = root.resolveSymbolicLinksSync();
    app = p.join(resolved, 'app');
    api = p.join(resolved, 'api');
    workspaceFile = p.join(resolved, 'team.lumide-workspace');
    await Directory(app).create();
    await Directory(api).create();
    await File(workspaceFile).writeAsString('{"folders": []}');
  });

  tearDown(() => root.delete(recursive: true));

  group('LaunchCommand', () {
    test('accepts --add with several folders', () {
      final results = LaunchCommand().argParser.parse(['--add', app, api]);

      expect(results['add'], isTrue);
      expect(results.rest, [app, api]);
    });

    test('takes folders without --add', () {
      final results = LaunchCommand().argParser.parse([app, api]);

      expect(results['add'], isFalse);
      expect(results.rest, [app, api]);
    });
  });

  group('lumideAppArguments', () {
    test('passes several folders on for one window', () {
      expect(lumideAppArguments([app, api]), [app, api]);
    });

    test('passes --add on before the folders', () {
      expect(lumideAppArguments([app, api], add: true), ['--add', app, api]);
    });

    test('keeps a single --add given after --', () {
      expect(
        lumideAppArguments(['--add', app], add: true),
        ['--add', app],
      );
      expect(lumideAppArguments(['--add', app]), ['--add', app]);
    });

    test('passes workspace files on as absolute paths', () {
      final relative = p.relative(workspaceFile);

      expect(lumideAppArguments([relative]), [workspaceFile]);
    });
  });

  group('installThenLaunchArguments', () {
    test('passes paths on to Lumide after --', () {
      expect(
        installThenLaunchArguments([app, api]),
        ['install', '--prompt', '--', app, api],
      );
    });

    test('passes --add on to Lumide', () {
      expect(
        installThenLaunchArguments(['--add', app]),
        ['install', '--prompt', '--', '--add', app],
      );
    });

    test('installs only without arguments', () {
      expect(installThenLaunchArguments([]), ['install', '--prompt']);
    });
  });
}
