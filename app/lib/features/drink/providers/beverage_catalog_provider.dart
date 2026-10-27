import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_api.dart';
import '../../../shared/models/beverage.dart';
import 'custom_beverage_provider.dart';

/// 后台发布的云端饮品目录（含容器图标）。
///
/// 启动先读本地缓存保证离线可用，随后联网刷新；刷新失败保留缓存。
/// 云端饮品的图标统一以 `url:` 前缀写进 containerId，由 SvgContainerIcon /
/// SvgContainerFill 按当前服务端地址解析，换隧道域名无需清缓存。
class BeverageCatalogNotifier extends StateNotifier<List<Beverage>> {
  BeverageCatalogNotifier(this.ref) : super(const []) {
    loaded = _init();
  }

  final Ref ref;

  static const _kKey = 'remote_beverages';

  /// 缓存读取完成信号
  late final Future<void> loaded;

  Future<void> _init() async {
    await _loadCache();
    await refresh();
  }

  Future<void> _loadCache() async {
    try {
      final storage = await ref.read(localStorageProvider.future);
      final raw = storage.prefs.getString(_kKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => _fromJson(Map<String, dynamic>.from(e)))
          .whereType<Beverage>()
          .toList();
      if (mounted) state = list;
    } catch (_) {
      // 缓存异常忽略，等联网刷新
    }
  }

  Future<void> _saveCache(List<Map<String, dynamic>> rows) async {
    try {
      final storage = await ref.read(localStorageProvider.future);
      await storage.prefs.setString(_kKey, jsonEncode(rows));
    } catch (_) {
      // 写缓存失败不影响展示
    }
  }

  /// 联网刷新目录（失败静默，沿用缓存）
  Future<void> refresh() async {
    try {
      final rows = await SyncApi.beverageCatalog();
      final list = rows.map(_fromJson).whereType<Beverage>().toList();
      if (!mounted) return;
      state = list;
      await _saveCache(rows);
    } catch (_) {
      // 离线：沿用缓存 / 内置预设
    }
  }

  Beverage? _fromJson(Map<String, dynamic> m) {
    final id = (m['id'] ?? '').toString();
    final name = (m['name'] ?? '').toString();
    if (id.isEmpty || name.isEmpty) return null;
    final icon = (m['iconUrl'] ?? '').toString().trim();
    return Beverage(
      id: id,
      category: _category(m['category']?.toString()),
      name: name,
      defaultMl: (m['defaultMl'] as num?)?.toInt() ?? 250,
      liquidColor: _color(m['liquidColor']?.toString()),
      hydrationRatio: (m['hydrationRatio'] as num?)?.toDouble(),
      containerId: icon.isEmpty ? null : 'url:$icon',
    );
  }

  static BeverageCategory _category(String? raw) {
    for (final c in BeverageCategory.values) {
      if (c.name == raw) return c;
    }
    return BeverageCategory.water;
  }

  /// 解析 `#RRGGBB` / `#AARRGGBB` / `#RGB`
  static Color? _color(String? raw) {
    var hex = (raw ?? '').trim().replaceFirst('#', '');
    if (hex.isEmpty) return null;
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }
}

final beverageCatalogProvider =
    StateNotifierProvider<BeverageCatalogNotifier, List<Beverage>>((ref) {
  return BeverageCatalogNotifier(ref);
});

/// 完整饮品库 = 内置预设（可被后台同 id 覆盖）+ 后台新增饮品 + 自定义饮品
final beverageLibraryProvider = Provider<List<Beverage>>((ref) {
  final remote = ref.watch(beverageCatalogProvider);
  final customs = ref.watch(customBeveragesProvider);
  final remoteById = {for (final b in remote) b.id: b};
  final presetIds = {for (final p in Beverage.presets) p.id};
  return [
    for (final p in Beverage.presets)
      if (remoteById[p.id] != null) _mergePreset(p, remoteById[p.id]!) else p,
    for (final b in remote)
      if (!presetIds.contains(b.id)) b,
    ...customs,
  ];
});

/// 后台覆盖内置款：只替换运营可配的展示字段，营养/动画等仍用内置值
Beverage _mergePreset(Beverage preset, Beverage remote) {
  return Beverage(
    id: preset.id,
    category: remote.category,
    name: remote.name,
    defaultMl: remote.defaultMl,
    icon: preset.icon,
    liquidColor: remote.liquidColor ?? preset.liquidColor,
    hydrationRatio: remote.hydrationRatio ?? preset.hydrationRatio,
    templateId: preset.templateId,
    animation: preset.animation,
    containerId: remote.containerId ?? preset.containerId,
    calories: preset.calories,
    caffeineMg: preset.caffeineMg,
    alcoholPercent: preset.alcoholPercent,
  );
}
