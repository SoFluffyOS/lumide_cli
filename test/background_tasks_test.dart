import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:lumide/src/background_tasks.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Directory temp;
  late File destination;
  late List<Future<void> Function(HttpRequest)> behaviours;

  final data = Uint8List.fromList(
      List<int>.generate(300 * 1024, (i) => (i * 7) % 256, growable: false));
  final half = data.length ~/ 2;

  Uri url() => Uri.parse('http://${server.address.host}:${server.port}/a.zip');

  Future<void> full(HttpRequest r) async {
    r.response
      ..statusCode = 200
      ..contentLength = data.length
      ..add(data);
    await r.response.close();
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumide_background_test_');
    destination = File(p.join(temp.path, 'a.zip'));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var index = 0;
    server.listen((request) => behaviours[index++](request));
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  group('downloadInBackground', () {
    test('downloads the file and reports progress', () async {
      behaviours = [full];
      final progress = <double>[];
      await downloadInBackground(url(), destination, onProgress: progress.add);
      expect(destination.readAsBytesSync(), data);
      expect(progress, isNotEmpty);
      // Progress is throttled: far fewer updates than network chunks.
      expect(progress.length, lessThanOrEqualTo(201));
    });

    test('retries a cut-off transfer and reports the retry', () async {
      behaviours = [
        (r) async {
          r.response
            ..statusCode = 200
            ..contentLength = data.length;
          final socket = await r.response.detachSocket();
          socket.add(data.sublist(0, half));
          await socket.flush();
          socket.destroy();
        },
        full,
      ];
      final retries = <(int, int, Object)>[];
      await downloadInBackground(
        url(),
        destination,
        onRetry: (next, max, error) => retries.add((next, max, error)),
        initialRetryDelay: Duration.zero,
      );
      expect(destination.readAsBytesSync(), data);
      expect(retries, hasLength(1));
      expect(retries.single.$1, 2);
    });

    test('a server error keeps its type (ProcessException)', () async {
      behaviours = [
        (r) async {
          r.response.statusCode = 404;
          await r.response.close();
        },
      ];
      await expectLater(
        downloadInBackground(url(), destination),
        throwsA(isA<ProcessException>()),
      );
    });

    test('a stalled transfer keeps its type (TimeoutException)', () async {
      final stalled = Completer<void>();
      behaviours = [
        (r) async {
          r.response
            ..statusCode = 200
            ..contentLength = data.length
            ..add(data.sublist(0, half));
          await r.response.flush();
          await stalled.future;
        },
      ];
      await expectLater(
        downloadInBackground(
          url(),
          destination,
          stallTimeout: const Duration(milliseconds: 300),
          maxAttempts: 1,
        ),
        throwsA(isA<TimeoutException>()),
      );
      stalled.complete();
    });

    test('a refused connection keeps its type (SocketException)', () async {
      final port = server.port;
      await server.close(force: true);
      await expectLater(
        downloadInBackground(
          Uri.parse('http://127.0.0.1:$port/a.zip'),
          destination,
          maxAttempts: 1,
        ),
        throwsA(isA<SocketException>()),
      );
      // tearDown closes it again; give it a fresh server.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });
  });

  group('extractArchiveInBackground', () {
    Future<String> writeZip(Map<String, String> files) async {
      final archive = Archive();
      files.forEach((name, content) {
        archive.addFile(ArchiveFile.string(name, content));
      });
      final zip = File(p.join(temp.path, 'test.zip'));
      await zip.writeAsBytes(ZipEncoder().encode(archive));
      return zip.path;
    }

    test('extracts the archive', () async {
      final out = p.join(temp.path, 'out');
      await extractArchiveInBackground(
        await writeZip({'Lumide/Lumide.exe': 'exe'}),
        out,
      );
      expect(File(p.join(out, 'Lumide.exe')).readAsStringSync(), 'exe');
    });

    test('an unsafe archive keeps its error type (FormatException)', () async {
      await expectLater(
        extractArchiveInBackground(
            await writeZip({'../evil.txt': 'x'}), p.join(temp.path, 'out')),
        throwsFormatException,
      );
    });
  });
}
