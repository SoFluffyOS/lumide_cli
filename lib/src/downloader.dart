/// Downloads release assets, resuming interrupted transfers.
library;

import 'dart:io';

import 'package:lumide/src/network_retry.dart';

/// Downloads [uri] into [destination] in one attempt.
///
/// If [destination] already holds part of the file (from an attempt that
/// was cut off), only the rest is requested with an HTTP `Range` header. A
/// server that ignores the range answers `200` with the whole file, which
/// then simply replaces the partial one.
///
/// Throws a transient error ([HttpException] / [TimeoutException] /
/// [SocketException]) when the transfer is cut off or stalls for
/// [stallTimeout], so callers can retry with [retryOnNetworkError]; the
/// partial file is kept for the next attempt. A server error such as 404
/// throws a [ProcessException], which is not retried.
Future<void> downloadWithResume(
  Uri uri,
  File destination, {
  void Function(double progress)? onProgress,
  Duration stallTimeout = kNetworkStallTimeout,
}) async {
  final client = HttpClient()..connectionTimeout = kNetworkConnectionTimeout;

  try {
    final alreadyDownloaded =
        destination.existsSync() ? destination.lengthSync() : 0;
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'lumide-cli');
    if (alreadyDownloaded > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$alreadyDownloaded-');
    }
    final response = await request.close().timeout(stallTimeout);

    if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      // The partial file cannot be continued: start over next attempt.
      await response.drain<void>();
      await destination.delete();
      throw const HttpException('Download could not be resumed.');
    }

    final resumed = alreadyDownloaded > 0 &&
        response.statusCode == HttpStatus.partialContent;
    if (response.statusCode != HttpStatus.ok && !resumed) {
      await response.drain<void>();
      throw ProcessException(
        'download',
        [uri.toString()],
        'Failed to download $uri (HTTP ${response.statusCode}).',
        response.statusCode,
      );
    }

    var downloaded = resumed ? alreadyDownloaded : 0;
    final total =
        response.contentLength < 0 ? -1 : response.contentLength + downloaded;

    final sink = destination.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    try {
      // A connection that stops sending data fails after [stallTimeout]
      // instead of hanging forever.
      await for (final chunk in response.timeout(stallTimeout)) {
        downloaded += chunk.length;
        if (total > 0) onProgress?.call(downloaded / total);
        sink.add(chunk);
      }
    } finally {
      // Keep what arrived so the next attempt can resume from there.
      await sink.close();
    }

    if (total > 0 && downloaded != total) {
      throw HttpException(
          'Download ended early ($downloaded of $total bytes).');
    }
  } finally {
    client.close(force: true);
  }
}
