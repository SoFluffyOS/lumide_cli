import 'dart:async';
import 'dart:io';

import 'package:lumide/src/network_retry.dart';
import 'package:test/test.dart';

void main() {
  late List<Duration> waits;
  Future<void> fakeSleep(Duration d) async => waits.add(d);

  setUp(() => waits = []);

  test('returns at once when the first attempt works', () async {
    var calls = 0;
    final result = await retryOnNetworkError(() async {
      calls++;
      return 'ok';
    }, sleep: fakeSleep);
    expect(result, 'ok');
    expect(calls, 1);
    expect(waits, isEmpty);
  });

  test('retries connection errors with a growing pause', () async {
    var calls = 0;
    final retries = <int>[];
    final result = await retryOnNetworkError(
      () async {
        calls++;
        if (calls < 3) throw const SocketException('timed out');
        return 'ok';
      },
      onRetry: (next, max, _) => retries.add(next),
      sleep: fakeSleep,
    );
    expect(result, 'ok');
    expect(calls, 3);
    expect(retries, [2, 3]);
    expect(waits, [const Duration(seconds: 1), const Duration(seconds: 2)]);
  });

  test('gives up after the last attempt and rethrows the error', () async {
    var calls = 0;
    await expectLater(
      retryOnNetworkError(() async {
        calls++;
        throw TimeoutException('slow');
      }, sleep: fakeSleep),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, kNetworkMaxAttempts);
    expect(waits, [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]);
  });

  test('does not retry errors where the server answered', () async {
    var calls = 0;
    await expectLater(
      retryOnNetworkError(() async {
        calls++;
        throw const FormatException('bad payload');
      }, sleep: fakeSleep),
      throwsFormatException,
    );
    expect(calls, 1);
    expect(waits, isEmpty);
  });

  test('isTransientNetworkError', () {
    expect(isTransientNetworkError(const SocketException('x')), isTrue);
    expect(isTransientNetworkError(TimeoutException('x')), isTrue);
    expect(isTransientNetworkError(const HttpException('x')), isTrue);
    expect(
      isTransientNetworkError(
          const RedirectException('Redirect limit exceeded', [])),
      isFalse,
    );
    expect(isTransientNetworkError(const FormatException('x')), isFalse);
    expect(isTransientNetworkError(Exception('x')), isFalse);
  });
}
