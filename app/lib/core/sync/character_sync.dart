import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_api.dart';

/// 云端角色目录的本地缓存（离线优先，与容器图标库同一套思路）
///
/// - 从未联网同步过：角色页使用安装包内置的 [characterCategories] / [characters]
/// - 联网同步成功后：以服务端分类与已发布角色为准——缺的 SVG 下载到应用
///   私有目录，服务端已删除的角色同步从列表中移除并清理缓存文件；
///   安装包内置文件无法删除，只是不再出现在列表中
class CharacterStore {
  static const _kCategories = 'character_categories_v1';
  static const _kItems = 'character_items_v1';
  static const _kSynced = 'character_synced_v1';
  static const _dirName = 'characters';

  static String? _dirPath;
  static bool _synced = false;
  static List<Map<String, dynamic>> _categories = const [];
  static List<Map<String, dynamic>> _items = const [];
  static bool _running = false;

  /// 启动时调用一次：准备缓存目录并读回上次同步结果
  static Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/$_dirName');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dirPath = dir.path;
      final prefs = await SharedPreferences.getInstance();
      _synced = prefs.getBool(_kSynced) ?? false;
      _categories = _decodeList(prefs.getString(_kCategories));
      _items = _decodeList(prefs.getString(_kItems));
    } catch (e) {
      debugPrint('[Characters] init failed: $e');
    }
  }

  /// 是否已有服务端下发的目录（false = 用安装包内置角色）
  static bool get hasRemoteList => _synced;

  static List<Map<String, dynamic>> get categories => _categories;

  static List<Map<String, dynamic>> get items => _items;

  /// 已下载到本地的角色 SVG 路径（不存在返回 null）
  static String? filePathSync(String characterId) {
    final dir = _dirPath;
    if (dir == null || !_isSafeName(characterId)) return null;
    final file = File('$dir/$characterId.svg');
    return file.existsSync() ? file.path : null;
  }

  /// 拉取服务端目录 → 下载缺失素材 → 清理服务端已删除的缓存
  /// 返回本地是否有变化（用于刷新角色目录 provider）
  static Future<bool> sync() async {
    final dirPath = _dirPath;
    if (_running || dirPath == null) return false;
    _running = true;
    try {
      final data = await SyncApi.characterCatalog();
      final rawCategories = data['categories'];
      final rawItems = data['items'];
      if (rawCategories is! List || rawItems is! List) return false;

      final categories = rawCategories
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final items = rawItems
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      // 服务端还没配置任何分类：视为未同步，继续用内置角色
      if (categories.isEmpty) return false;

      final dir = Directory(dirPath);
      final keep = <String>{};
      var changed = false;
      final bundled = await _bundledNames();

      for (final item in items) {
        final id = (item['id'] ?? item['code'] ?? '').toString();
        if (!_isSafeName(id)) continue;
        keep.add(id);
        final file = File('$dirPath/$id.svg');
        if (file.existsSync() || bundled.contains(id)) continue;
        final url = (item['assetUrl'] ?? '').toString();
        if (url.isEmpty) continue;
        if (await _download(url, file)) changed = true;
      }

      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.svg')) continue;
        final base = entity.uri.pathSegments.last;
        final id = base.substring(0, base.length - 4);
        if (!keep.contains(id)) {
          entity.deleteSync();
          changed = true;
        }
      }

      final oldJson = jsonEncode(_items);
      final nextJson = jsonEncode(items);
      if (oldJson != nextJson) changed = true;

      _categories = categories;
      _items = items;
      _synced = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCategories, jsonEncode(categories));
      await prefs.setString(_kItems, nextJson);
      await prefs.setBool(_kSynced, true);
      return changed;
    } catch (e) {
      // 离线 / 服务端异常：保留上次同步结果，不打扰用户
      debugPrint('[Characters] sync failed: $e');
      return false;
    } finally {
      _running = false;
    }
  }

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// 安装包里自带的角色 id（不含 .svg）
  static Future<Set<String>> _bundledNames() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      const prefix = 'assets/images/characters/';
      return manifest
          .listAssets()
          .where((a) => a.startsWith(prefix) && a.endsWith('.svg'))
          .map((a) => a.substring(prefix.length, a.length - 4))
          .toSet();
    } catch (_) {
      return const {};
    }
  }

  static Future<bool> _download(String url, File file) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse(
        url.startsWith('http') ? url : '${SyncApi.baseUrl}$url',
      );
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) return false;
      final bytes = await response.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      if (bytes.isEmpty) return false;
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      return true;
    } catch (e) {
      debugPrint('[Characters] download failed: $url $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// 只接受简单 id，防止路径穿越
  static bool _isSafeName(String name) {
    if (name.isEmpty || name.length > 100) return false;
    if (name.contains('/') || name.contains('\\') || name.contains('..')) {
      return false;
    }
    return true;
  }
}
