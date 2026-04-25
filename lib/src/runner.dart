/// Command runner for the Lumide CLI.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:lumide/src/app_installer.dart';
import 'package:lumide/src/commands/doctor_command.dart';
import 'package:lumide/src/commands/fox_command.dart';
import 'package:lumide/src/commands/install_command.dart';
import 'package:lumide/src/commands/launch_command.dart';
import 'package:lumide/src/constants.dart';
import 'package:lumide/src/pub_client.dart';

Future<int> runLumide(List<String> arguments) async {
  final runner =
      CommandRunner<int>(
          'lumide',
          'Standalone CLI for installing and launching Lumide.',
        )
        ..addCommand(InstallCommand())
        ..addCommand(LaunchCommand())
        ..addCommand(DoctorCommand())
        ..addCommand(FoxCommand());

  // Background update check
  final updateCheck = _checkUpdateInBackground();

  var effectiveArguments = arguments;
  if (effectiveArguments.isEmpty) {
    final appPath = defaultLumideAppPath();
    final entity = FileSystemEntity.typeSync(appPath);
    if (entity == FileSystemEntityType.notFound) {
      effectiveArguments = ['install', '--prompt'];
    } else {
      effectiveArguments = ['launch'];
    }
  } else {
    final firstArg = effectiveArguments.first;
    final knownCommands = runner.commands.keys.toSet()
      ..addAll(['help', '-h', '--help']);
    if (!knownCommands.contains(firstArg)) {
      effectiveArguments = ['launch', ...effectiveArguments];
    }
  }

  // Redirect to install if Lumide is missing during a launch attempt
  if (effectiveArguments.isNotEmpty && effectiveArguments.first == 'launch') {
    final appPath = defaultLumideAppPath();
    final entity = FileSystemEntity.typeSync(appPath);
    if (entity == FileSystemEntityType.notFound) {
      final remainingArgs = effectiveArguments.skip(1).toList();
      effectiveArguments = ['install', '--prompt', ...remainingArgs];
    }
  }

  try {
    final result = await runner.run(effectiveArguments);

    // After command finishes, show update notification if found
    try {
      final latestVersion = await updateCheck.timeout(
        const Duration(milliseconds: 500),
      );
      if (latestVersion != null && !latestVersion.contains(kLumideCliVersion)) {
        stdout.writeln(
          '\n[!] A new version of Lumide CLI is available: $latestVersion\n'
          '    Run `dart pub global activate lumide` to update.',
        );
      }
    } catch (_) {
      // Ignore update check errors/timeouts
    }

    return result ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    return 64;
  } on UnsupportedError catch (error) {
    stderr.writeln(error.message);
    return 1;
  } on ProcessException catch (error) {
    stderr.writeln(error.message);
    return 1;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    return 1;
  } on Exception catch (error) {
    stderr.writeln(error);
    return 1;
  }
}

Future<String?> _checkUpdateInBackground() async {
  try {
    const client = PubClient();
    return await client.fetchLatestVersion();
  } catch (_) {
    return null;
  }
}
