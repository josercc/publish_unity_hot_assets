import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 从旧包名本地缓存回退读取 SharedPreferences，并写回当前包以完成迁移。
///
/// 旧包：`com.example.publishUnityHotAssets`
/// 新包：`com.winner.publishUnityHotAssets`
class LegacyPrefsStore {
  static const legacyMacBundleId = 'com.example.publishUnityHotAssets';
  static const legacyWindowsCompany = 'com.example';
  static const legacyWindowsProduct = 'publish_unity_hot_assets';
  static const flutterPrefix = 'flutter.';

  static Map<String, String>? _legacyCache;
  static Future<void>? _loading;

  /// 先读当前包；没有则读旧包缓存，命中后写回当前包。
  static Future<String?> getString(SharedPreferences sp, String key) async {
    final local = sp.getString(key);
    if (local != null && local.trim().isNotEmpty) {
      return local;
    }

    final legacy = await _legacyValue(key);
    if (legacy != null && legacy.trim().isNotEmpty) {
      await sp.setString(key, legacy);
      // ignore: avoid_print
      print('[LegacyPrefs] migrated key=$key from $legacyMacBundleId');
      return legacy;
    }
    return local;
  }

  /// 把旧包中当前包缺失的键一次性迁过来（启动时调用）。
  static Future<int> migrateMissingKeys(SharedPreferences sp) async {
    await _ensureLegacyLoaded();
    final legacy = _legacyCache;
    if (legacy == null || legacy.isEmpty) return 0;

    var count = 0;
    for (final entry in legacy.entries) {
      final existing = sp.getString(entry.key);
      if (existing != null && existing.trim().isNotEmpty) continue;
      if (entry.value.trim().isEmpty) continue;
      await sp.setString(entry.key, entry.value);
      count++;
    }
    if (count > 0) {
      // ignore: avoid_print
      print(
        '[LegacyPrefs] migrated $count keys from $legacyMacBundleId '
        '→ current package',
      );
    }
    return count;
  }

  static Future<String?> _legacyValue(String key) async {
    await _ensureLegacyLoaded();
    return _legacyCache?[key];
  }

  static Future<void> _ensureLegacyLoaded() {
    return _loading ??= _loadLegacyCache().then((map) {
      _legacyCache = map;
    });
  }

  static Future<Map<String, String>> _loadLegacyCache() async {
    try {
      if (Platform.isMacOS || Platform.isIOS) {
        return await _loadAppleLegacy();
      }
      if (Platform.isWindows) {
        return await _loadWindowsLegacy();
      }
      if (Platform.isLinux) {
        return await _loadLinuxLegacy();
      }
    } catch (e) {
      // ignore: avoid_print
      print('[LegacyPrefs] load legacy failed: $e');
    }
    return {};
  }

  static Future<Map<String, String>> _loadAppleLegacy() async {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return {};

    final candidates = <String>[
      p.join(home, 'Library', 'Preferences', '$legacyMacBundleId.plist'),
      p.join(
        home,
        'Library',
        'Containers',
        legacyMacBundleId,
        'Data',
        'Library',
        'Preferences',
        '$legacyMacBundleId.plist',
      ),
    ];

    for (final path in candidates) {
      final file = File(path);
      if (!await file.exists()) continue;
      final result = await Process.run(
        'plutil',
        ['-convert', 'json', '-o', '-', path],
      );
      if (result.exitCode != 0) continue;
      final stdout = '${result.stdout}'.trim();
      if (stdout.isEmpty) continue;
      final decoded = jsonDecode(stdout);
      if (decoded is! Map) continue;
      final map = _normalizeFlutterPrefMap(Map<String, dynamic>.from(decoded));
      if (map.isNotEmpty) return map;
    }
    return {};
  }

  static Future<Map<String, String>> _loadWindowsLegacy() async {
    final candidates = <String>[];
    final appData = Platform.environment['APPDATA'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (appData != null && appData.isNotEmpty) {
      candidates.add(
        p.join(
          appData,
          legacyWindowsCompany,
          legacyWindowsProduct,
          'shared_preferences.json',
        ),
      );
    }
    if (localAppData != null && localAppData.isNotEmpty) {
      candidates.add(
        p.join(
          localAppData,
          legacyWindowsCompany,
          legacyWindowsProduct,
          'shared_preferences.json',
        ),
      );
    }

    for (final path in candidates) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        final map =
            _normalizeFlutterPrefMap(Map<String, dynamic>.from(decoded));
        if (map.isNotEmpty) return map;
      } catch (_) {
        continue;
      }
    }
    return {};
  }

  static Future<Map<String, String>> _loadLinuxLegacy() async {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return {};
    final candidates = [
      p.join(
        home,
        '.local',
        'share',
        legacyWindowsCompany,
        legacyWindowsProduct,
        'shared_preferences.json',
      ),
      p.join(
        home,
        '.local',
        'share',
        legacyMacBundleId,
        'shared_preferences.json',
      ),
    ];
    for (final path in candidates) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        final map =
            _normalizeFlutterPrefMap(Map<String, dynamic>.from(decoded));
        if (map.isNotEmpty) return map;
      } catch (_) {
        continue;
      }
    }
    return {};
  }

  /// 去掉 `flutter.` 前缀，只保留字符串值。
  static Map<String, String> _normalizeFlutterPrefMap(
    Map<String, dynamic> raw,
  ) {
    final out = <String, String>{};
    for (final entry in raw.entries) {
      var key = entry.key.toString();
      if (key.startsWith(flutterPrefix)) {
        key = key.substring(flutterPrefix.length);
      }
      final value = entry.value;
      if (value is String) {
        out[key] = value;
      } else if (value != null) {
        out[key] = value.toString();
      }
    }
    return out;
  }
}
