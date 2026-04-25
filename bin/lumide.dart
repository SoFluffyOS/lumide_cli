import 'dart:io';

import 'package:lumide/lumide.dart';

Future<void> main(List<String> arguments) async {
  final exitCodeValue = await runLumide(arguments);
  exitCode = exitCodeValue;
}
