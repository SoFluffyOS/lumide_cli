import 'dart:convert';
import 'dart:io';

class PubClient {
  const PubClient();

  static const String _pubApiUrl = 'https://pub.dev/api/packages/lumide';

  Future<String?> fetchLatestVersion() async {
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(_pubApiUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'lumide-cli');
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final responseBody = await utf8.decodeStream(response);
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
