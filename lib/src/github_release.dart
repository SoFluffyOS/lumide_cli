/// GitHub release models used by the installer.
library;

class GithubRelease {
  const GithubRelease({required this.tagName, required this.assets});

  final String tagName;
  final List<GithubReleaseAsset> assets;

  factory GithubRelease.fromJson(Map<String, Object?> json) {
    final rawAssets = json['assets'];
    return GithubRelease(
      tagName: json['tag_name'] as String? ?? 'unknown',
      assets: switch (rawAssets) {
        final List<dynamic> assets => assets
            .whereType<Map<String, Object?>>()
            .map(GithubReleaseAsset.fromJson)
            .toList(),
        _ => const [],
      },
    );
  }
}

class GithubReleaseAsset {
  const GithubReleaseAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;

  factory GithubReleaseAsset.fromJson(Map<String, Object?> json) {
    return GithubReleaseAsset(
      name: json['name'] as String? ?? '',
      downloadUrl: json['browser_download_url'] as String? ?? '',
    );
  }
}
