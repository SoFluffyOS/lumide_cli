import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lumide/src/downloader.dart';
import 'package:lumide/src/network_retry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Directory temp;
  late File destination;
  final rangeHeaders = <String?>[];
  // What the fake server does for each request, in order.
  late List<Future<void> Function(HttpRequest)> behaviours;

  final data = Uint8List.fromList(
      List<int>.generate(200 * 1024, (i) => (i * 7) % 256, growable: false));
  final half = data.length ~/ 2;

  Uri url() => Uri.parse('http://${server.address.host}:${server.port}/a.zip');

  Future<void> full(HttpRequest r) async {
    r.response
      ..statusCode = 200
      ..contentLength = data.length
      ..add(data);
    await r.response.close();
  }

  Future<void> resumeFromRange(HttpRequest r) async {
    final range = r.headers.value(HttpHeaders.rangeHeader)!;
    final start = int.parse(range.substring('bytes='.length, range.length - 1));
    r.response
      ..statusCode = HttpStatus.partialContent
      ..headers.set(HttpHeaders.contentRangeHeader,
          'bytes $start-${data.length - 1}/${data.length}')
      ..contentLength = data.length - start
      ..add(data.sublist(start));
    await r.response.close();
  }

  Future<void> cutOffHalfway(HttpRequest r) async {
    r.response
      ..statusCode = 200
      ..contentLength = data.length;
    final socket = await r.response.detachSocket();
    socket.add(data.sublist(0, half));
    await socket.flush();
    socket.destroy();
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumide_download_test_');
    destination = File(p.join(temp.path, 'a.zip'));
    rangeHeaders.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var index = 0;
    server.listen((request) {
      rangeHeaders.add(request.headers.value(HttpHeaders.rangeHeader));
      behaviours[index++](request);
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  Future<void> download({Duration stall = kNetworkStallTimeout}) =>
      retryOnNetworkError(
        () => downloadWithResume(url(), destination, stallTimeout: stall),
        sleep: (_) async {},
      );

  test('downloads a file in one go', () async {
    behaviours = [full];
    final progress = <double>[];
    await downloadWithResume(url(), destination, onProgress: progress.add);
    expect(destination.readAsBytesSync(), data);
    expect(progress.last, 1.0);
    expect(rangeHeaders, [null]);
  });

  test('resumes where a cut-off attempt stopped', () async {
    behaviours = [cutOffHalfway, resumeFromRange];
    await download();
    expect(destination.readAsBytesSync(), data);
    expect(rangeHeaders, [null, 'bytes=$half-']);
  });

  test('starts over when the server ignores the range', () async {
    behaviours = [cutOffHalfway, full];
    await download();
    expect(destination.readAsBytesSync(), data);
    expect(rangeHeaders.last, 'bytes=$half-');
  });

  test('a stalled transfer fails with a timeout and keeps the part', () async {
    final stalled = Completer<void>();
    behaviours = [
      (r) async {
        r.response
          ..statusCode = 200
          ..contentLength = data.length
          ..add(data.sublist(0, half));
        await r.response.flush();
        await stalled.future; // never send the rest
      },
    ];
    await expectLater(
      downloadWithResume(url(), destination,
          stallTimeout: const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
    );
    expect(destination.lengthSync(), half);
    stalled.complete();
  });

  test('a 404 is reported and not retried', () async {
    behaviours = [
      (r) async {
        r.response.statusCode = 404;
        await r.response.close();
      },
    ];
    await expectLater(download(), throwsA(isA<ProcessException>()));
    expect(rangeHeaders, hasLength(1));
  });

  test('an unresumable part (416) is deleted and downloaded again', () async {
    destination.writeAsBytesSync(data.sublist(0, half));
    behaviours = [
      (r) async {
        r.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await r.response.close();
      },
      full,
    ];
    await download();
    expect(destination.readAsBytesSync(), data);
    expect(rangeHeaders, ['bytes=$half-', null]);
  });
}
