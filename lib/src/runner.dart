/// Command runner for the Lumide CLI.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:lumide/src/app_installer.dart';
import 'package:lumide/src/app_version.dart';
import 'package:lumide/src/commands/doctor_command.dart';
import 'package:lumide/src/commands/fox_command.dart';
import 'package:lumide/src/commands/install_command.dart';
import 'package:lumide/src/commands/launch_command.dart';
import 'package:lumide/src/constants.dart';
import 'package:lumide/src/pub_client.dart';

class _LumideCommandRunner extends CommandRunner<int> {
  _LumideCommandRunner()
      : super(
          'lumide',
          'Standalone CLI for installing and launching Lumide.',
        );

  @override
  String get invocation =>
      'lumide [--add] [<file or folder>...]\n       lumide <command> [arguments]';

  @override
  String get usageFooter => '''

Without a command, lumide launches Lumide with the files and folders given:
  lumide .                       Open the current folder.
  lumide app api web             Open one window with app as the first folder
                                 and api and web added to it.
  lumide --add api web           Add api and web to the window you used last.
  lumide team.lumide-workspace   Open a workspace file.''';
}

Future<int> runLumide(List<String> arguments) async {
  final runner = _LumideCommandRunner()
    ..addCommand(InstallCommand())
    ..addCommand(LaunchCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(FoxCommand());

  // Background update check
  final updateCheck = _checkUpdateInBackground();

  var effectiveArguments = arguments;
  if (effectiveArguments.isEmpty) {
    if (!isLumideApp(defaultLumideAppPath())) {
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
    if (!isLumideApp(defaultLumideAppPath())) {
      effectiveArguments = installThenLaunchArguments(
        effectiveArguments.skip(1).toList(),
      );
    }
  }

  try {
    final result = await runner.run(effectiveArguments);

    // After command finishes, show update notification if found
    try {
      final latestVersion = await updateCheck.timeout(
        const Duration(milliseconds: 500),
      );
      if (isUpToDate(kLumideCliVersion, latestVersion) == false) {
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

/// The `install` arguments that install Lumide, then launch it with the
/// `launch` arguments [launchArguments]. Install passes on what follows
/// `--`, so that launch options such as `--add` reach Lumide.
List<String> installThenLaunchArguments(List<String> launchArguments) {
  final add = launchArguments.contains(addFlag);
  final paths = [
    for (final argument in launchArguments)
      if (argument != addFlag && argument != '--') argument,
  ];
  return [
    'install',
    '--prompt',
    if (add || paths.isNotEmpty) '--',
    if (add) addFlag,
    ...paths,
  ];
}

Future<String?> _checkUpdateInBackground() async {
  try {
    const client = PubClient();
    return await client.fetchLatestVersion();
  } catch (_) {
    return null;
  }
}
