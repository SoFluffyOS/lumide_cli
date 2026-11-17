import 'dart:io';

import 'package:lumide/src/app_installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String target;

  String read(String path) => File(path).readAsStringSync();

  void write(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumide_replace_test_');
    target = p.join(temp.path, 'Lumide');
    write(p.join(target, 'Lumide.exe'), 'old');
  });

  tearDown(() => temp.delete(recursive: true));

  test('swaps in the new folder and removes the old one', () async {
    await replaceDirectory(
      target,
      (staging) async => write(p.join(staging, 'Lumide.exe'), 'new'),
    );

    expect(read(p.join(target, 'Lumide.exe')), 'new');
    expect(
        temp.listSync().map((entity) => p.basename(entity.path)), ['Lumide']);
  });

  test('keeps the current folder when filling fails', () async {
    await expectLater(
      replaceDirectory(target, (staging) async {
        write(p.join(staging, 'Lumide.exe'), 'half');
        throw const FileSystemException('extraction failed');
      }),
      throwsA(isA<FileSystemException>()),
    );

    expect(read(p.join(target, 'Lumide.exe')), 'old');
    expect(
        temp.listSync().map((entity) => p.basename(entity.path)), ['Lumide']);
  });

  test('creates the folder when there is none yet', () async {
    await Directory(target).delete(recursive: true);

    await replaceDirectory(
      target,
      (staging) async => write(p.join(staging, 'Lumide.exe'), 'new'),
    );

    expect(read(p.join(target, 'Lumide.exe')), 'new');
  });

  test('clears leftovers of an interrupted install', () async {
    write(p.join('$target.new', 'stale'), '');
    write(p.join('$target.old', 'stale'), '');

    await replaceDirectory(
      target,
      (staging) async => write(p.join(staging, 'Lumide.exe'), 'new'),
    );

    expect(Directory(target).listSync().map((e) => p.basename(e.path)),
        ['Lumide.exe']);
    expect(
        temp.listSync().map((entity) => p.basename(entity.path)), ['Lumide']);
  });
}
