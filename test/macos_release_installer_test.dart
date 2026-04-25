import 'package:lumide/src/macos_release_installer.dart';
import 'package:test/test.dart';

void main() {
  group('parseMountPoint', () {
    test('extracts mount point from plist output', () {
      const plist = '''
<plist version="1.0">
<array>
  <dict>
    <key>mount-point</key>
    <string>/Volumes/Lumide</string>
  </dict>
</array>
</plist>
''';

      expect(parseMountPoint(plist), '/Volumes/Lumide');
    });

    test('returns null when mount point is missing', () {
      expect(parseMountPoint('<plist></plist>'), isNull);
    });
  });
}
