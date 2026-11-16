import 'dart:io';

import 'package:lumide/src/app_installer.dart';
import 'package:lumide/src/constants.dart';
import 'package:lumide/src/install_location_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late Map<String, String> env;
  late String folder;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumide_use_existing_test_');
    // Point every per-OS config location at the temp folder.
    env = {
      'LOCALAPPDATA': temp.path,
      'USERPROFILE': temp.path,
      'HOME': temp.path,
      'XDG_CONFIG_HOME': temp.path,
    };
    folder = p.join(temp.path, 'apps');
  });

  tearDown(() => temp.delete(recursive: true));

  test('offers to use a folder nothing points at yet', () {
    expect(shouldOfferToUseExistingInstall(folder, env), isTrue);
  });

  test('offers again when a different folder is remembered', () async {
    await saveLumideInstallDirectory(p.join(temp.path, 'other'), env);
    expect(shouldOfferToUseExistingInstall(folder, env), isTrue);
  });

  test('does not offer when that folder is already remembered', () async {
    await saveLumideInstallDirectory(folder, env);
    expect(shouldOfferToUseExistingInstall(folder, env), isFalse);
  });

  test('does not offer when LUMIDE_INSTALL_DIR is set (it decides)', () {
    expect(
      shouldOfferToUseExistingInstall(
          folder, {...env, kLumideInstallDirEnvVar: p.join(temp.path, 'x')}),
      isFalse,
    );
    expect(
      shouldOfferToUseExistingInstall(
          folder, {...env, kLumideInstallDirEnvVar: folder}),
      isFalse,
    );
  });

  test('does not offer for the default folder when nothing is saved', () {
    expect(
      shouldOfferToUseExistingInstall(
          platformDefaultLumideInstallDirectory(), env),
      isFalse,
    );
  });
}
