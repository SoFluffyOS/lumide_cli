/// `lumide launch` implementation.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:lumide/src/app_installer.dart';

class LaunchCommand extends Command<int> {
  LaunchCommand() {
    argParser.addOption('app-path', help: 'Explicit path to Lumide.');
  }

  @override
  String get description => 'Launch Lumide.';

  @override
  String get name => 'launch';

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

    final passthroughArguments = argResults?.rest ?? const <String>[];
    final arguments = <String>[];

    if (Platform.isMacOS) {
      if (passthroughArguments.isNotEmpty) {
        final absoluteArgs = _resolveAbsoluteArgs(passthroughArguments);
        arguments.addAll([appPath, '--args', ...absoluteArgs]);
      } else {
        arguments.add(appPath);
      }
      await Process.start('open', arguments, mode: ProcessStartMode.detached);
      stdout.writeln('Launched Lumide from $appPath');
    } else if (Platform.isWindows) {
      if (passthroughArguments.isNotEmpty) {
        final absoluteArgs = _resolveAbsoluteArgs(passthroughArguments);
        arguments.addAll(absoluteArgs);
      }
      await Process.start(
        appPath,
        arguments,
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      stdout.writeln('Launched Lumide from $appPath');
    } else {
      // Linux
      if (passthroughArguments.isNotEmpty) {
        final absoluteArgs = _resolveAbsoluteArgs(passthroughArguments);
        arguments.addAll(absoluteArgs);
      }
      await Process.start(appPath, arguments, mode: ProcessStartMode.detached);
      stdout.writeln('Launched Lumide from $appPath');
    }

    return 0;
  }

  List<String> _resolveAbsoluteArgs(List<String> args) {
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
}
