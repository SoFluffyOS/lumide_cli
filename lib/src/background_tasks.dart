/// Download and extraction on a background isolate, because the install
/// screen's input loop (nocterm on Windows) pauses the main isolate for up
/// to 16 ms at a time, which slowed downloads about 16x.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:lumide/src/downloader.dart';
import 'package:lumide/src/io_helpers.dart';
import 'package:lumide/src/network_retry.dart';

/// [downloadWithResume] with [retryOnNetworkError], on a background isolate.
///
/// [onProgress] and [onRetry] are called on the calling isolate. Errors are
/// rethrown with their original type (e.g. [SocketException],
/// [ProcessException]).
Future<void> downloadInBackground(
  Uri uri,
  File destination, {
  void Function(double progress)? onProgress,
  void Function(int nextAttempt, int maxAttempts, Object error)? onRetry,
  Duration stallTimeout = kNetworkStallTimeout,
  int maxAttempts = kNetworkMaxAttempts,
  Duration initialRetryDelay = const Duration(seconds: 1),
}) async {
  final updates = ReceivePort();
  updates.listen((message) {
    switch (message) {
      case final double progress:
        onProgress?.call(progress);
      case (final int nextAttempt, final int max, final String error):
        onRetry?.call(nextAttempt, max, error);
    }
  });
  try {
    await _download(
      updates.sendPort,
      uri.toString(),
      destination.path,
      stallTimeout,
      maxAttempts,
      initialRetryDelay,
    );
  } finally {
    updates.close();
  }
}

// Top-level, so the closure given to Isolate.run captures only these
// sendable arguments.
Future<void> _download(
  SendPort updates,
  String uri,
  String path,
  Duration stallTimeout,
  int maxAttempts,
  Duration initialRetryDelay,
) {
  return Isolate.run(() async {
    // Send at most ~200 progress updates instead of one per network chunk.
    var lastSent = -1.0;
    await retryOnNetworkError(
      () => downloadWithResume(
        Uri.parse(uri),
        File(path),
        stallTimeout: stallTimeout,
        onProgress: (progress) {
          if ((progress - lastSent).abs() >= 0.005 || progress >= 1) {
            lastSent = progress;
            updates.send(progress);
          }
        },
      ),
      maxAttempts: maxAttempts,
      initialDelay: initialRetryDelay,
      onRetry: (nextAttempt, max, error) =>
          updates.send((nextAttempt, max, error.toString())),
    );
  });
}

/// [extractArchive] on a background isolate.
Future<void> extractArchiveInBackground(
  String archivePath,
  String destinationDir,
) {
  return Isolate.run(() => extractArchive(archivePath, destinationDir));
}
