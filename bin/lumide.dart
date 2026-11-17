import 'dart:io';

import 'package:lumide/lumide.dart';

Future<void> main(List<String> arguments) async {
  final exitCodeValue = await runLumide(arguments);

  // Don't wait for the background update check to finish. Flush first so
  // no output is lost (like dart-lang/pub's flushThenExit).
  await Future.wait([stdout.close(), stderr.close()]);
  exit(exitCodeValue);
}
