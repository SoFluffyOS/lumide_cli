/// Fetches Lumide releases from GitHub.
library;

import 'dart:convert';
import 'dart:io';

import 'package:lumide/src/constants.dart';
import 'package:lumide/src/github_release.dart';

class GithubReleaseClient {
  const GithubReleaseClient();

  Future<GithubRelease> fetchLatestRelease({required String repository}) async {
    final uri = Uri.parse(
      '$kGithubApiBaseUrl/repos/$repository/releases/latest',
    );

    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'lumide-cli');

      final response = await request.close();
      final responseBody = await utf8.decodeStream(response);

      if (response.statusCode != HttpStatus.ok) {
        throw LumideCliException(
          'Failed to fetch latest release from $repository '
          '(HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(responseBody);
      if (decoded case final Map<String, Object?> map) {
        return GithubRelease.fromJson(map);
      }

      throw const LumideCliException('GitHub API returned an invalid payload.');
    } finally {
      httpClient.close(force: true);
    }
  }
}

class LumideCliException implements Exception {
  const LumideCliException(this.message);

  final String message;

  @override
  String toString() => message;
}
