/// Reads the version of an installed Lumide and compares versions.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// The version of the Lumide at [appPath], or `null` when it can't be told.
///
/// - Windows: the version resource of Lumide.exe (what Explorer shows under
///   Properties > Details).
/// - macOS: `CFBundleShortVersionString` from `Lumide.app/Contents/Info.plist`.
/// - Linux: the release archive has no version file, so always `null`.
String? installedLumideVersion(String appPath, {String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  try {
    final version = switch (os) {
      'windows' => _windowsProductVersion(appPath),
      'macos' => _macOsBundleVersion(appPath),
      _ => null,
    };
    return version == null ? null : normalizeVersion(version);
  } catch (_) {
    return null;
  }
}

/// `defaults` reads both XML and binary plists.
String? _macOsBundleVersion(String appPath) {
  if (!File(p.join(appPath, 'Contents', 'Info.plist')).existsSync()) {
    return null;
  }
  final result = Process.runSync('defaults', [
    'read',
    p.join(appPath, 'Contents', 'Info'),
    'CFBundleShortVersionString',
  ]);
  final output = (result.stdout as String).trim();
  return result.exitCode == 0 && output.isNotEmpty ? output : null;
}

/// The product version from the file's VS_FIXEDFILEINFO, as `major.minor.patch`
/// (plus `.build` when it isn't 0).
String? _windowsProductVersion(String path) {
  if (!File(path).existsSync()) return null;
  return using((arena) {
    final pathPtr = path.toNativeUtf16(allocator: arena);
    final unused = arena<Uint32>();
    final size = _getFileVersionInfoSize(pathPtr, unused);
    if (size == 0) return null;
    final data = arena<Uint8>(size);
    if (_getFileVersionInfo(pathPtr, 0, size, data.cast()) == 0) return null;

    final info = arena<Pointer<Void>>();
    final length = arena<Uint32>();
    final root = r'\'.toNativeUtf16(allocator: arena);
    if (_verQueryValue(data.cast(), root, info, length) == 0 ||
        length.value < 13 * 4) {
      return null;
    }
    // VS_FIXEDFILEINFO: dwSignature, dwStrucVersion, dwFileVersionMS/LS,
    // dwProductVersionMS/LS, ...
    final fixed = info.value.cast<Uint32>();
    if (fixed[0] != 0xFEEF04BD) return null;
    final ms = fixed[4];
    final ls = fixed[5];
    final parts = [ms >> 16, ms & 0xFFFF, ls >> 16, ls & 0xFFFF];
    if (parts.every((part) => part == 0)) return null;
    return (parts.last == 0 ? parts.take(3) : parts).join('.');
  });
}

// Top-level finals load on first use, which only happens on Windows.
final _versionDll = DynamicLibrary.open('version.dll');

final _getFileVersionInfoSize = _versionDll.lookupFunction<
    Uint32 Function(Pointer<Utf16>, Pointer<Uint32>),
    int Function(Pointer<Utf16>, Pointer<Uint32>)>('GetFileVersionInfoSizeW');

final _getFileVersionInfo = _versionDll.lookupFunction<
    Int32 Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>),
    int Function(Pointer<Utf16>, int, int, Pointer<Void>)>(
  'GetFileVersionInfoW',
);

final _verQueryValue = _versionDll.lookupFunction<
    Int32 Function(
        Pointer<Void>, Pointer<Utf16>, Pointer<Pointer<Void>>, Pointer<Uint32>),
    int Function(Pointer<Void>, Pointer<Utf16>, Pointer<Pointer<Void>>,
        Pointer<Uint32>)>('VerQueryValueW');

/// [version] without a leading `v` and without build metadata
/// (`v0.25.0+12` -> `0.25.0`).
String normalizeVersion(String version) {
  var normalized = version.trim();
  if (normalized.startsWith('v') || normalized.startsWith('V')) {
    normalized = normalized.substring(1);
  }
  final plus = normalized.indexOf('+');
  return plus < 0 ? normalized : normalized.substring(0, plus);
}

/// Compares two dotted versions number by number (missing parts count as
/// 0, so `0.25` equals `0.25.0`). `null` when either isn't plain numbers,
/// e.g. a pre-release like `0.26.0-beta`.
int? compareVersions(String a, String b) {
  List<int>? parse(String v) {
    final parts = normalizeVersion(v).split('.');
    final numbers = parts.map(int.tryParse).toList();
    return numbers.contains(null) ? null : numbers.cast<int>();
  }

  final left = parse(a);
  final right = parse(b);
  if (left == null || right == null) return null;
  for (var i = 0; i < left.length || i < right.length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

/// Whether [installed] is at least [latest]; `null` when either is unknown
/// or they can't be compared (then only identical versions count).
bool? isUpToDate(String? installed, String? latest) {
  if (installed == null || latest == null) return null;
  final comparison = compareVersions(installed, latest);
  if (comparison != null) return comparison >= 0;
  return normalizeVersion(installed) == normalizeVersion(latest) ? true : null;
}

/// The installed and latest versions in a few words, e.g. "0.25.0, up to
/// date" or "0.25.0, 0.26.0 available".
String describeVersions(String? installed, String? latest) {
  final version =
      installed == null ? 'version unknown' : normalizeVersion(installed);
  if (latest == null) return '$version, could not check the latest release';
  final latestVersion = normalizeVersion(latest);
  return switch (isUpToDate(installed, latest)) {
    true => '$version, up to date',
    false => '$version, $latestVersion available',
    null => '$version, latest release $latestVersion',
  };
}
