import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:lumide/src/app_installer.dart';
import 'package:lumide/src/constants.dart';
import 'package:lumide/src/lumide_process_environment.dart';
import 'package:lumide/src/pub_client.dart';
import 'package:path/path.dart' as p;

class DoctorCommand extends Command<int> {
  DoctorCommand() {
    argParser
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Print process environment and executable resolution details.',
        negatable: false,
      )
      ..addFlag(
        'show-path',
        help: 'Print every PATH entry. Intended for deep diagnostics.',
        negatable: false,
      )
      ..addOption(
        'dart-path',
        help: 'Test the custom Dart executable configured in Lumide.',
        valueHelp: 'path-or-command',
      )
      ..addOption(
        'plugin-path',
        help: 'Run the same `dart pub get` process used during plugin startup.',
        valueHelp: 'directory',
      );
  }

  @override
  String get description => 'Show information about the installed tooling.';

  @override
  String get name => 'doctor';

  @override
  Future<int> run() async {
    final verbose = argResults?['verbose'] as bool? ?? false;
    final showPath = argResults?['show-path'] as bool? ?? false;
    final customDart = argResults?['dart-path'] as String?;
    final pluginPath = argResults?['plugin-path'] as String?;

    stdout.writeln('Checking Lumide environment...\n');
    await LumideProcessEnvironment.initialize();

    // 1. CLI Version
    stdout.write('[✓] Lumide CLI: $kLumideCliVersion');
    try {
      final client = const PubClient();
      final latestVersion = await client.fetchLatestVersion();
      if (latestVersion == null) {
        stdout.writeln(' (Unable to check for updates)');
      } else if (latestVersion.contains(kLumideCliVersion)) {
        stdout.writeln(' (Up to date)');
      } else {
        stdout.writeln(' (New version available: $latestVersion)');
      }
    } catch (_) {
      stdout.writeln(' (Unable to check for updates)');
    }

    // 2. Lumide App
    final appPath = defaultLumideAppPath();
    final entity = FileSystemEntity.typeSync(appPath);
    if (entity != FileSystemEntityType.notFound) {
      stdout.writeln('[✓] Lumide App: Installed at $appPath');
    } else {
      stdout.writeln(
        '[✗] Lumide App: Not found. Run `lumide install` to set it up.',
      );
    }

    // This intentionally uses bare `dart`, matching LocalPluginLoader.
    final environment = LumideProcessEnvironment.environment;
    final resolvedDart = await LumideProcessEnvironment.resolveExecutable(
      'dart',
    );
    await _checkDart(
      label: 'Dart SDK (plugin startup)',
      executable: 'dart',
      environment: environment,
      resolvedExecutable: resolvedDart,
      verbose: verbose,
    );

    if (customDart != null && customDart.trim().isNotEmpty) {
      final command = customDart.trim().split(RegExp(r'\s+'));
      final executable = command.first;
      final baseArguments = command.skip(1).toList();
      final resolvedCustom = await LumideProcessEnvironment.resolveExecutable(
        executable,
      );
      await _checkDart(
        label: 'Dart SDK (custom setting)',
        executable: resolvedCustom ?? executable,
        baseArguments: baseArguments,
        environment: environment,
        resolvedExecutable: resolvedCustom,
        verbose: verbose,
      );
      stdout.writeln(
        '[!] Local plugin `pub get` uses bare `dart`; the custom SDK setting '
        'is not used by that Lumide process.',
      );
    }

    if (pluginPath != null && pluginPath.trim().isNotEmpty) {
      await _checkPluginPubGet(pluginPath.trim(), environment);
    }

    // 4. Flutter SDK
    try {
      final result = await Process.run(
        'flutter',
        ['--version'],
        environment: environment,
      );
      if (result.exitCode == 0) {
        final firstLine = result.stdout.toString().split('\n').first;
        stdout.writeln('[✓] Flutter SDK: ${firstLine.split(' ').elementAt(1)}');
      } else {
        stdout.writeln('[!] Flutter SDK: Found but check failed.');
      }
    } catch (_) {
      stdout.writeln(
        '[!] Flutter SDK: Not found in PATH (optional for Lumide).',
      );
    }

    if (verbose || showPath) {
      _printProcessDetails(
        environment,
        resolvedDart,
        showAllPathEntries: showPath,
      );
    }

    stdout.writeln('\nDoctor check finished.');
    return 0;
  }

  Future<void> _checkDart({
    required String label,
    required String executable,
    required Map<String, String> environment,
    required String? resolvedExecutable,
    required bool verbose,
    List<String> baseArguments = const [],
  }) async {
    final arguments = [...baseArguments, '--version'];
    if (verbose) {
      stdout.writeln('    command: $executable ${arguments.join(' ')}');
      stdout.writeln(
        '    resolved executable: ${resolvedExecutable ?? '<not found>'}',
      );
    }

    try {
      final result = await Process.run(
        executable,
        arguments,
        environment: environment,
      );
      final output = '${result.stdout}${result.stderr}'.trim();
      if (result.exitCode == 0) {
        stdout.writeln('[✓] $label: ${output.replaceAll('\n', ' ')}');
        return;
      }
      stdout.writeln('[✗] $label: exited with code ${result.exitCode}');
      if (output.isNotEmpty) stdout.writeln('    $output');
    } on ProcessException catch (error) {
      stdout.writeln('[✗] $label: ${error.message}');
      stdout.writeln('    executable: ${error.executable}');
      stdout.writeln('    arguments: ${error.arguments.join(' ')}');
      stdout.writeln('    OS error code: ${error.errorCode}');
      stdout.writeln(
        '    resolved executable: '
        '${resolvedExecutable ?? '<not found in Lumide PATH>'}',
      );
    }
  }

  Future<void> _checkPluginPubGet(
    String pluginPath,
    Map<String, String> environment,
  ) async {
    final absolutePath = p.absolute(pluginPath);
    stdout.writeln('\nPlugin startup process probe:');
    stdout.writeln('    command: dart pub get');
    stdout.writeln('    working directory: $absolutePath');
    if (!await Directory(absolutePath).exists()) {
      stdout.writeln('[✗] Plugin path does not exist or is not a directory.');
      return;
    }

    try {
      final result = await Process.run(
        'dart',
        ['pub', 'get'],
        workingDirectory: absolutePath,
        environment: environment,
      );
      stdout.writeln(
        result.exitCode == 0
            ? '[✓] Plugin `dart pub get` completed successfully.'
            : '[✗] Plugin `dart pub get` exited with code ${result.exitCode}.',
      );
      final output = '${result.stdout}${result.stderr}'.trim();
      if (output.isNotEmpty) stdout.writeln(output);
    } on ProcessException catch (error) {
      stdout.writeln('[✗] Plugin process failed to start: ${error.message}');
      stdout.writeln('    executable: ${error.executable}');
      stdout.writeln('    arguments: ${error.arguments.join(' ')}');
      stdout.writeln('    OS error code: ${error.errorCode}');
      stdout.writeln('    working directory: $absolutePath');
    }
  }

  void _printProcessDetails(
    Map<String, String> environment,
    String? resolvedDart, {
    required bool showAllPathEntries,
  }) {
    final pathKey = Platform.isWindows ? 'Path' : 'PATH';
    final path = environment[pathKey] ?? '';
    final separator = Platform.isWindows ? ';' : ':';
    stdout.writeln('\nProcess diagnostics:');
    stdout.writeln(
      '    OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    stdout.writeln('    CLI runtime: ${Platform.resolvedExecutable}');
    stdout.writeln('    working directory: ${Directory.current.path}');
    stdout.writeln('    environment key: $pathKey');
    stdout.writeln('    resolved dart: ${resolvedDart ?? '<not found>'}');
    final pathEntries = path
        .split(separator)
        .where((entry) => entry.isNotEmpty)
        .map(p.normalize)
        .toSet()
        .toList();
    final existingEntries =
        pathEntries.where((entry) => Directory(entry).existsSync()).toList();
    final missingCount = pathEntries.length - existingEntries.length;
    stdout.writeln(
      '    $pathKey: ${pathEntries.length} entries '
      '(${existingEntries.length} existing, $missingCount missing)',
    );

    if (showAllPathEntries) {
      stdout.writeln('    All $pathKey entries:');
      for (final entry in pathEntries) {
        final status = Directory(entry).existsSync() ? '[exists]' : '[missing]';
        stdout.writeln('      $status $entry');
      }
    } else {
      final toolEntries =
          existingEntries.where(_containsDartOrFlutter).toList();
      stdout.writeln('    Dart/Flutter $pathKey entries:');
      if (toolEntries.isEmpty) stdout.writeln('      <none>');
      for (final entry in toolEntries) {
        stdout.writeln('      $entry');
      }
    }
    if (Platform.isWindows) {
      stdout.writeln(
        '    PATHEXT: ${environment['PATHEXT'] ?? '<not set>'}',
      );
    }
  }

  bool _containsDartOrFlutter(String directory) {
    final extensions =
        Platform.isWindows ? const ['.exe', '.bat', '.cmd', ''] : const [''];
    for (final tool in const ['dart', 'flutter']) {
      for (final extension in extensions) {
        if (File(p.join(directory, '$tool$extension')).existsSync()) {
          return true;
        }
      }
    }
    return false;
  }
}
