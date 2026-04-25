import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:lumide/src/app_installer.dart';
import 'package:lumide/src/constants.dart';
import 'package:lumide/src/pub_client.dart';

class DoctorCommand extends Command<int> {
  @override
  String get description => 'Show information about the installed tooling.';

  @override
  String get name => 'doctor';

  @override
  Future<int> run() async {
    stdout.writeln('Checking Lumide environment...\n');

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

    // 3. Dart SDK
    try {
      final result = await Process.run('dart', ['--version']);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim().split(' ').elementAt(3);
        stdout.writeln('[✓] Dart SDK: $version');
      } else {
        stdout.writeln('[✗] Dart SDK: Found but returned error.');
      }
    } catch (_) {
      stdout.writeln('[✗] Dart SDK: Not found in PATH.');
    }

    // 4. Flutter SDK
    try {
      final result = await Process.run('flutter', ['--version']);
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

    stdout.writeln('\nDoctor check finished.');
    return 0;
  }
}
