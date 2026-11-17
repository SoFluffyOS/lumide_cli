import 'dart:convert';
import 'dart:io';

import 'package:lumide/src/network_retry.dart';

class PubClient {
  const PubClient();

  static const String _pubApiUrl = 'https://pub.dev/api/packages/lumide';

  /// The latest published version, or `null` when pub.dev can't be reached.
  /// Gives up when connecting or the reply stalls for longer than the usual
  /// network timeouts, instead of waiting indefinitely.
  Future<String?> fetchLatestVersion() async {
    final httpClient = HttpClient()
      ..connectionTimeout = kNetworkConnectionTimeout;
    try {
      final request = await httpClient.getUrl(Uri.parse(_pubApiUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'lumide-cli');
      final response = await request.close().timeout(kNetworkStallTimeout);

      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final responseBody =
          await utf8.decodeStream(response.timeout(kNetworkStallTimeout));
      final decoded = jsonDecode(responseBody);

      if (decoded case {'latest': {'version': final String version}}) {
        return version;
      }

      return null;
    } catch (_) {
      return null;
    } finally {
      httpClient.close(force: true);
    }
  }
}
