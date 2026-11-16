/// Fetches Lumide releases from GitHub.
library;

import 'dart:convert';
import 'dart:io';

import 'package:lumide/src/constants.dart';
import 'package:lumide/src/github_release.dart';
import 'package:lumide/src/network_retry.dart';

class GithubReleaseClient {
  const GithubReleaseClient();

  Future<GithubRelease> fetchLatestRelease({
    required String repository,
    void Function(int nextAttempt, int maxAttempts, Object error)? onRetry,
    int maxAttempts = kNetworkMaxAttempts,
  }) {
    return retryOnNetworkError(
      () => _fetchLatestRelease(repository),
      onRetry: onRetry,
      maxAttempts: maxAttempts,
    );
  }

  Future<GithubRelease> _fetchLatestRelease(String repository) async {
    final uri = Uri.parse(
      '$kGithubApiBaseUrl/repos/$repository/releases/latest',
    );

    // Same connection timeout as downloads, so a stalled connection fails
    // (and is retried) instead of hanging.
    final httpClient = HttpClient()
      ..connectionTimeout = kNetworkConnectionTimeout;
    try {
      final request = await httpClient.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'lumide-cli');

      final response = await request.close().timeout(kNetworkStallTimeout);
      final responseBody =
          await utf8.decodeStream(response.timeout(kNetworkStallTimeout));

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
