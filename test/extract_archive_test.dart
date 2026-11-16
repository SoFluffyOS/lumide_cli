import 'dart:io';

import 'package:archive/archive.dart';
import 'package:lumide/src/io_helpers.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumide_extract_test_');
  });

  tearDown(() => temp.delete(recursive: true));

  Future<String> writeZip(Map<String, String> files) async {
    final archive = Archive();
    files.forEach((name, content) {
      archive.addFile(ArchiveFile.string(name, content));
    });
    final zip = File(p.join(temp.path, 'test.zip'));
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    return zip.path;
  }

  test('extracts a normal archive', () async {
    final out = p.join(temp.path, 'out');
    await extractArchive(
        await writeZip({'Lumide/readme.txt': 'hi', 'a/b/c.txt': 'x'}), out);
    expect(File(p.join(out, 'Lumide', 'readme.txt')).readAsStringSync(), 'hi');
    expect(File(p.join(out, 'a', 'b', 'c.txt')).existsSync(), isTrue);
  });

  test('refuses entries that escape the destination (zip slip)', () async {
    final out = p.join(temp.path, 'out');
    final zip = await writeZip({'ok.txt': 'ok', '../evil.txt': 'evil'});

    await expectLater(extractArchive(zip, out), throwsFormatException);
    expect(File(p.join(temp.path, 'evil.txt')).existsSync(), isFalse);
    // Nothing is written when any entry is unsafe.
    expect(File(p.join(out, 'ok.txt')).existsSync(), isFalse);
  });

  group('archiveEntryTarget', () {
    final root = p.normalize(p.absolute(p.join('build', 'root')));

    test('keeps normal entries inside the root', () {
      expect(archiveEntryTarget(root, 'Lumide/Lumide.exe'),
          p.join(root, 'Lumide', 'Lumide.exe'));
    });

    test('rejects parent-directory and absolute entries', () {
      expect(() => archiveEntryTarget(root, '../x'), throwsFormatException);
      expect(
          () => archiveEntryTarget(root, 'a/../../x'), throwsFormatException);
      expect(() => archiveEntryTarget(root, p.absolute('elsewhere', 'x')),
          throwsFormatException);
    });
  });
}
