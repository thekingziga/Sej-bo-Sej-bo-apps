import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Compares dotted version strings numerically.
///
/// String comparison is wrong in the one case that matters: `'1.10.0'` sorts
/// *before* `'1.9.0'` lexically, so a naive gate would stop forcing updates the
/// moment the minor version reached double digits - and would do it silently.
///
/// Returns <0 if [a] is older than [b], 0 if equal, >0 if newer. Missing parts
/// count as zero, so `1.8` == `1.8.0`. Anything non-numeric (a `+build` suffix,
/// a `-beta` tag) is ignored from that segment on, since the server compares
/// release versions and the build number is Play's business.
int compareVersions(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

List<int> _parts(String v) {
  final out = <int>[];
  for (final chunk in v.trim().split('.')) {
    // Take the leading digits only: "1.8.0+10" -> [1, 8, 0], "2.0-rc1" -> [2, 0].
    final digits = RegExp(r'^\d+').firstMatch(chunk)?.group(0);
    if (digits == null) break;
    out.add(int.parse(digits));
  }
  return out;
}

/// This build's own identity, read from the platform rather than hardcoded so
/// the number on screen can never drift from the number that shipped.
class AppVersion {
  const AppVersion({required this.version, required this.build});

  /// e.g. "1.8.0" - the versionName, which is what the server compares.
  final String version;

  /// e.g. "10" - Play's versionCode. Shown next to the version because it is
  /// what identifies a specific upload in Play Console.
  final String build;

  static AppVersion? _cached;

  /// Cached after the first read: this never changes during a run, and the
  /// platform channel call is not free.
  static Future<AppVersion> load() async {
    if (_cached != null) return _cached!;
    try {
      final info = await PackageInfo.fromPlatform();
      return _cached = AppVersion(version: info.version, build: info.buildNumber);
    } catch (_) {
      // Tests and any platform without the plugin: not worth failing over a
      // label, so fall back to something obviously placeholder.
      return _cached = const AppVersion(version: '0.0.0', build: '0');
    }
  }

  @visibleForTesting
  static set cachedForTest(AppVersion? v) => _cached = v;

  /// "v1.8.0 (10)"
  String get display => 'v$version ($build)';

  @override
  String toString() => display;
}
