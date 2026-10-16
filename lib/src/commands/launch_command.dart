/// `lumide launch` implementation.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:lumide/src/app_installer.dart';

/// Flag Lumide reads to add the folders it is given to the workspace of the
/// window used last, instead of opening them in a window of their own.
const String addFlag = '--add';

class LaunchCommand extends Command<int> {
  LaunchCommand() {
    argParser
      ..addOption('app-path', help: 'Explicit path to Lumide.')
      ..addFlag(
        'add',
        negatable: false,
        help: 'Add the folders to the Lumide window you used last, or open '
            'them in a new window when none runs.',
      );
  }

  @override
  String get description => '''
Launch Lumide, opening files and folders.

  lumide .                       Open the current folder.
  lumide app api web             Open one window with app as the first folder
                                 and api and web added to it.
  lumide app lib/main.dart       Open app and the file in it.
  lumide --add api web           Add api and web to the window you used last.
  lumide team.lumide-workspace   Open a workspace file.''';

  @override
  String get name => 'launch';

  @override
  String get invocation => 'lumide [launch] [--add] [<file or folder>...]';

  @override
  Future<int> run() async {
    final explicitPath = argResults?['app-path'] as String?;
    final appPath = explicitPath == null || explicitPath.isEmpty
        ? defaultLumideAppPath()
        : explicitPath;

    final entity = FileSystemEntity.typeSync(appPath);
    if (entity == FileSystemEntityType.notFound) {
      throw FileSystemException('Lumide was not found.', appPath);
    }

    final appArguments = lumideAppArguments(
      argResults?.rest ?? const <String>[],
      add: argResults?['add'] == true,
    );
    final arguments = <String>[];

    if (Platform.isMacOS) {
      arguments.add('-n');
      if (appArguments.isNotEmpty) {
        arguments.addAll([appPath, '--args', ...appArguments]);
      } else {
        arguments.add(appPath);
      }
      await Process.start('open', arguments, mode: ProcessStartMode.detached);
      stdout.writeln('Launched Lumide from $appPath');
    } else if (Platform.isWindows) {
      arguments.addAll(appArguments);
      await Process.start(
        appPath,
        arguments,
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      stdout.writeln('Launched Lumide from $appPath');
    } else {
      // Linux
      arguments.addAll(appArguments);
      await Process.start(appPath, arguments, mode: ProcessStartMode.detached);
      stdout.writeln('Launched Lumide from $appPath');
    }

    return 0;
  }
}

/// The arguments Lumide is launched with: [passthrough] with its paths made
/// absolute, after [addFlag] when [add] is true.
///
/// Every path is passed on as is, files such as `*.lumide-workspace` files
/// included: Lumide decides how to open it.
List<String> lumideAppArguments(
  List<String> passthrough, {
  bool add = false,
}) {
  final arguments = resolveAbsoluteArgs(passthrough);
  if (!add || arguments.contains(addFlag)) return arguments;
  return [addFlag, ...arguments];
}

/// [args] with the paths among them made absolute, resolving symbolic links
/// of existing files and folders. Options are kept as is.
List<String> resolveAbsoluteArgs(List<String> args) {
  return args.map((arg) {
    if (arg.startsWith('-')) return arg;
    try {
      final absolutePath = File(arg).absolute.path;
      final type = FileSystemEntity.typeSync(absolutePath);
      if (type != FileSystemEntityType.notFound) {
        return type == FileSystemEntityType.file
            ? File(absolutePath).resolveSymbolicLinksSync()
            : Directory(absolutePath).resolveSymbolicLinksSync();
      }
      return absolutePath;
    } catch (_) {
      return arg;
    }
  }).toList();
}
