import 'package:lumide/src/app_installer.dart';
import 'package:lumide/src/io_helpers.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Trimmed copy of the file shipped in Lumide-Linux-0.25.0-x86_64.tar.gz.
  const shipped = '''
[Desktop Entry]
Version=1.0
Type=Application
Name=Lumide
Exec=lumide %U
Icon=io.sofluffy.lumide
Terminal=false
Actions=new-window;

[Desktop Action new-window]
Name=New Window
Exec=lumide --empty
''';

  group('patchLinuxDesktopEntry', () {
    test('points every Exec line at the installed app, keeping arguments', () {
      final patched = patchLinuxDesktopEntry(shipped,
          executable: '/home/u/.local/opt/lumide/Lumide',
          iconName: 'io.sofluffy.lumide');
      expect(
          patched, contains('\nExec="/home/u/.local/opt/lumide/Lumide" %U\n'));
      expect(patched,
          contains('\nExec="/home/u/.local/opt/lumide/Lumide" --empty\n'));
      expect(patched, contains('\nIcon=io.sofluffy.lumide\n'));
      expect(patched, contains('\nName=New Window\n'));
    });

    test('does not touch TryExec or other keys that end in Exec', () {
      final patched = patchLinuxDesktopEntry('TryExec=lumide\nExec=lumide\n',
          executable: '/opt/Lumide');
      expect(patched, 'TryExec=lumide\nExec="/opt/Lumide"\n');
    });

    test('replaces an already quoted program', () {
      final patched = patchLinuxDesktopEntry('Exec="/old path/Lumide" %U\n',
          executable: '/new/Lumide');
      expect(patched, 'Exec="/new/Lumide" %U\n');
    });

    test('leaves Icon alone without an icon name', () {
      final patched = patchLinuxDesktopEntry(shipped, executable: '/x/Lumide');
      expect(patched, contains('\nIcon=io.sofluffy.lumide\n'));
    });
  });

  group('quoteDesktopExecArgument', () {
    test('quotes paths with spaces', () {
      expect(quoteDesktopExecArgument('/home/u/My Apps/Lumide'),
          '"/home/u/My Apps/Lumide"');
    });

    test(r'escapes ", `, $ and \ as the spec requires', () {
      expect(quoteDesktopExecArgument(r'/a"b`c$d\e'), r'"/a\"b\`c\$d\\\\e"');
    });
  });

  group('linuxDataHome', () {
    test('uses an absolute XDG_DATA_HOME', () {
      expect(linuxDataHome({'XDG_DATA_HOME': '/data/u'}), '/data/u');
    });

    test('ignores an unset, empty or relative XDG_DATA_HOME', () {
      for (final xdg in [null, '', 'relative/dir']) {
        final env = {'HOME': '/home/u', if (xdg != null) 'XDG_DATA_HOME': xdg};
        expect(linuxDataHome(env), p.join('/home/u', '.local', 'share'));
      }
    });
  });
}
