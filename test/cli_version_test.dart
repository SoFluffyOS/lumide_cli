import 'dart:io';

import 'package:lumide/src/constants.dart';
import 'package:test/test.dart';

void main() {
  test('kLumideCliVersion matches the pubspec version', () {
    // Otherwise every command reports the current release as an update.
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1);
    expect(kLumideCliVersion, version);
  });
}
