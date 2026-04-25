import 'package:lumide/src/github_release.dart';
import 'package:lumide/src/release_asset_selector.dart';
import 'package:test/test.dart';

void main() {
  test('selectInstallAsset picks dmg asset on macOS', () {
    final assets = [
      const GithubReleaseAsset(
        name: 'lumide-notes.txt',
        downloadUrl: 'https://example.com/notes.txt',
      ),
      const GithubReleaseAsset(
        name: 'Lumide.dmg',
        downloadUrl: 'https://example.com/Lumide.dmg',
      ),
    ];

    final asset = selectInstallAsset(assets);
    expect(asset.name, 'Lumide.dmg');
  });
}
