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

  group('wrapper folder', () {
    Future<String> extract(Map<String, String> files) async {
      final out = p.join(temp.path, 'out');
      await extractArchive(await writeZip(files), out);
      return out;
    }

    test('drops the folder that wraps everything (Lumide 0.25 layout)',
        () async {
      final out = await extract({
        'Lumide/Lumide.exe': 'exe',
        'Lumide/data/icudtl.dat': 'icu',
      });
      expect(File(p.join(out, 'Lumide.exe')).readAsStringSync(), 'exe');
      expect(File(p.join(out, 'data', 'icudtl.dat')).existsSync(), isTrue);
      expect(Directory(p.join(out, 'Lumide')).existsSync(), isFalse);
    });

    test('keeps archives without a wrapper folder as they are', () async {
      final out = await extract({'Lumide.exe': 'exe', 'data/a.dat': 'a'});
      expect(File(p.join(out, 'Lumide.exe')).readAsStringSync(), 'exe');
      expect(File(p.join(out, 'data', 'a.dat')).existsSync(), isTrue);
    });

    test('ignores macOS metadata next to the wrapper folder', () async {
      final out = await extract({
        'Lumide/Lumide': 'bin',
        '__MACOSX/Lumide/._Lumide': 'junk',
      });
      expect(File(p.join(out, 'Lumide')).readAsStringSync(), 'bin');
      expect(Directory(p.join(out, '__MACOSX')).existsSync(), isFalse);
    });

    test('still refuses entries that escape after stripping', () async {
      final out = p.join(temp.path, 'out');
      await expectLater(
        extractArchive(
            await writeZip({'Lumide/a': 'a', 'Lumide/../../evil.txt': 'x'}),
            out),
        throwsFormatException,
      );
      expect(File(p.join(temp.path, 'evil.txt')).existsSync(), isFalse);
    });
  });

  group('singleTopLevelDirectory', () {
    test('finds the one wrapper folder', () {
      expect(singleTopLevelDirectory(['Lumide/', 'Lumide/a', 'Lumide/b/c']),
          'Lumide');
      expect(singleTopLevelDirectory(['./Lumide/a', './Lumide/b']), 'Lumide');
      expect(singleTopLevelDirectory([r'Lumide\a.exe', r'Lumide\b']), 'Lumide');
    });

    test('is null for several top-level items or a single file', () {
      expect(singleTopLevelDirectory(['a/x', 'b/y']), isNull);
      expect(singleTopLevelDirectory(['Lumide/a', 'readme.txt']), isNull);
      expect(singleTopLevelDirectory(['Lumide']), isNull);
      expect(singleTopLevelDirectory(['Lumide/']), isNull);
      expect(singleTopLevelDirectory(<String>[]), isNull);
    });

    test('is null for unsafe names, so they are checked unchanged', () {
      expect(singleTopLevelDirectory(['../x/a', '../x/b']), isNull);
      expect(singleTopLevelDirectory(['/abs/a', '/abs/b']), isNull);
    });
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
