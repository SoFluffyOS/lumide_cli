/// Retries for flaky network connections.
library;

import 'dart:async';
import 'dart:io';

/// How long opening a connection may take, including the DNS lookup.
/// 30 s matches Cargo's default `http.timeout`. A shorter limit such as 10 s
/// is too tight: when one DNS server does not answer (common with VPN
/// adapters), Windows takes about 11 s to fall back to the next one.
const Duration kNetworkConnectionTimeout = Duration(seconds: 30);

/// How many times a request is tried in total; one more than Cargo's
/// default of 3, since short outages on VPNs and Wi-Fi are common.
const int kNetworkMaxAttempts = 4;

/// How long a connection may go without sending any data (headers or the
/// next chunk of a download) before it counts as stalled.
const Duration kNetworkStallTimeout = Duration(seconds: 30);

/// Connection-level failures (no answer, connection dropped, timed out) are
/// worth retrying. Errors where the server did answer (e.g. HTTP 404) are not,
/// and neither is a redirect loop or too many redirects ([RedirectException]),
/// which a retry would only repeat.
bool isTransientNetworkError(Object error) => switch (error) {
      RedirectException() => false,
      SocketException() || TimeoutException() || HttpException() => true,
      _ => false,
    };

/// Runs [action] and retries it on transient network errors, waiting
/// [initialDelay] before the second attempt and doubling the wait after that.
///
/// [onRetry] is told which attempt comes next. Any other error, or the last
/// failed attempt, is rethrown unchanged.
Future<T> retryOnNetworkError<T>(
  Future<T> Function() action, {
  int maxAttempts = kNetworkMaxAttempts,
  Duration initialDelay = const Duration(seconds: 1),
  void Function(int nextAttempt, int maxAttempts, Object error)? onRetry,
  Future<void> Function(Duration delay)? sleep,
}) async {
  final wait = sleep ?? (delay) => Future<void>.delayed(delay);
  var delay = initialDelay;
  for (var attempt = 1;; attempt++) {
    try {
      return await action();
    } catch (error) {
      if (attempt >= maxAttempts || !isTransientNetworkError(error)) rethrow;
      onRetry?.call(attempt + 1, maxAttempts, error);
      await wait(delay);
      delay *= 2;
    }
  }
}
