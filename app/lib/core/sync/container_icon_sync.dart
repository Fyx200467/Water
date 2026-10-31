import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_api.dart';

/// 云端容器图标库的本地缓存（离线优先）
///
/// - 从未联网同步过：图标选择页使用安装包内置的 `assets/images/containers`
/// - 联网同步成功后：以服务端列表为准——缺的图标下载到应用私有目录，
///   服务端已删除的本地缓存文件同步清除；安装包内置文件无法删除，只是
///   不再出现在列表中（历史饮品的 containerId 仍可正常渲染）
class ContainerIconStore {
  static const _kIds = 'container_icon_ids_v1';
  static const _kSynced = 'container_icon_synced_v1';
  static const _dirName = 'container_icons';

  static String? _dirPath;
  static List<String> _ids = const [];
  static bool _synced = false;
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
      _ids = prefs.getStringList(_kIds) ?? const [];
    } catch (e) {
      debugPrint('[Icons] init failed: $e');
    }
  }

  /// 是否已有服务端下发的列表（false = 用安装包内置图标）
  static bool get hasRemoteList => _synced;

  /// 服务端列表（纯文件名，不含 svg: 前缀，已排序）
  static List<String> get remoteNames => _ids;

  /// 已下载到本地的图标文件路径（不存在返回 null）
  static String? filePathSync(String containerId) {
    final dir = _dirPath;
    if (dir == null) return null;
    final name = containerId.startsWith('svg:')
        ? containerId.substring(4)
        : containerId;
    if (!_isSafeName(name)) return null;
    final file = File('$dir/$name.svg');
    return file.existsSync() ? file.path : null;
  }

  /// 拉取服务端列表 → 下载缺失图标 → 清理服务端已删除的缓存
  /// 返回本地文件是否有增删（用于刷新图标列表缓存）
  static Future<bool> sync() async {
    final dirPath = _dirPath;
    if (_running || dirPath == null) return false;
    _running = true;
    try {
      final items = await SyncApi.containerCatalog();
      final dir = Directory(dirPath);
      final keep = <String>{};
      var changed = false;

      // 安装包内置的图标视为「本地已有」，不必重复下载
      final bundled = await _bundledNames();

      for (final item in items) {
        final name = (item['id'] ?? '').toString();
        if (!_isSafeName(name)) continue;
        keep.add(name);
        final file = File('$dirPath/$name.svg');
        if (file.existsSync() || bundled.contains(name)) continue;
        final url = (item['url'] ?? '').toString();
        if (url.isEmpty) continue;
        if (await _download(url, file)) changed = true;
      }

      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.svg')) continue;
        final base = entity.uri.pathSegments.last;
        final name = base.substring(0, base.length - 4);
        if (!keep.contains(name)) {
          entity.deleteSync();
          changed = true;
        }
      }

      _ids = keep.toList()..sort();
      _synced = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kIds, _ids);
      await prefs.setBool(_kSynced, true);
      return changed;
    } catch (e) {
      // 离线 / 服务端异常：保留上次同步结果，不打扰用户
      debugPrint('[Icons] sync failed: $e');
      return false;
    } finally {
      _running = false;
    }
  }

  /// 安装包里自带的容器图标文件名（不含 .svg）
  static Future<Set<String>> _bundledNames() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      const prefix = 'assets/images/containers/';
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
      // 服务端已做权威校验，这里再兜一层：体积异常或含危险节点直接丢弃，
      // 保留本地旧图标，避免损坏/恶意文件进入渲染
      if (bytes.length > 128 * 1024 || !_looksSafeSvg(bytes)) {
        debugPrint('[Icons] rejected unsafe svg: $url');
        return false;
      }
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      return true;
    } catch (e) {
      debugPrint('[Icons] download failed: $url $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// SVG 兜底检查：必须是单个 svg 根、无脚本/外链/动画等危险内容
  static bool _looksSafeSvg(List<int> bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: true).toLowerCase();
      if (!text.contains('<svg')) return false;
      if (text.contains('<!doctype') || text.contains('<!entity')) {
        return false;
      }
      if (text.contains('<script') ||
          text.contains('<foreignobject') ||
          text.contains('<image') ||
          text.contains('<animate')) {
        return false;
      }
      final hrefs = RegExp('href\\s*=\\s*["\']([^"\']*)').allMatches(text);
      for (final m in hrefs) {
        final value = m.group(1) ?? '';
        if (!value.startsWith('#')) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 只接受简单文件名，防止路径穿越
  static bool _isSafeName(String name) {
    if (name.isEmpty || name.length > 100) return false;
    if (name.contains('/') || name.contains('\\') || name.contains('..')) {
      return false;
    }
    return true;
  }
}
