/// Resolves release assets for the current platform.
library;

import 'dart:io';

import 'package:lumide/src/github_release.dart';

GithubReleaseAsset selectInstallAsset(List<GithubReleaseAsset> assets) {
  if (Platform.isMacOS) {
    return _pickByExtension(assets, '.dmg');
  }
  if (Platform.isWindows) {
    return _pickByExtension(assets, '.zip');
  }
  if (Platform.isLinux) {
    return _pickByExtension(assets, '.tar.gz');
  }

  throw UnsupportedError(
    'lumide install currently supports macOS, Windows, and Linux.',
  );
}

GithubReleaseAsset _pickByExtension(
  List<GithubReleaseAsset> assets,
  String extension,
) {
  for (final asset in assets) {
    if (asset.name.toLowerCase().endsWith(extension)) {
      return asset;
    }
  }

  throw StateError('No release asset ending in $extension was found.');
}
