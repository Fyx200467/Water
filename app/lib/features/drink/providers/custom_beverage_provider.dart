import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/account_settings.dart';
import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../shared/models/beverage.dart';
import '../../home/providers/home_providers.dart';

/// 自定义饮品列表（账号级偏好，供首页快捷栏 / 加量页 / 管理页共用）
class CustomBeverageListNotifier extends StateNotifier<List<Beverage>> {
  CustomBeverageListNotifier(this.ref) : super(const []) {
    loaded = _load();
  }

  final Ref ref;

  /// 磁盘加载完成信号：完成前 state 是空列表，小组件同步若不等待，
  /// 自定义饮品槽位会查不到（回退到 all.first）并推错图标/名称
  late final Future<void> loaded;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.readAccountSetting(AccountSettingKeys.customBeverages);
    if (raw is! List || raw.isEmpty) return;
    try {
      state = raw
          .map((e) => _fromMap((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      // 数据异常时忽略，保持空列表
    }
  }

  Beverage _fromMap(Map<String, dynamic> m) {
    final category = BeverageCategory.values.firstWhere(
      (c) => c.name == m['category'],
      orElse: () => BeverageCategory.water,
    );
    final colorInt = m['liquidColor'] as int?;
    final ratio = (m['hydrationRatio'] as num?)?.toDouble();
    return Beverage(
      id: m['id'] as String,
      category: category,
      name: m['name'] as String,
      defaultMl: (m['defaultMl'] as num?)?.toInt() ?? 250,
      icon: category.icon,
      liquidColor: colorInt == null ? null : Color(colorInt),
      hydrationRatio: ratio,
      templateId: m['templateId'] as String?,
      animation: m['animation'] as String?,
      volumePreset: m['volumePreset'] as String?,
      containerId: m['containerId'] as String?,
      calories: (m['calories'] as num?)?.toInt(),
      caffeineMg: (m['caffeineMg'] as num?)?.toInt(),
      alcoholPercent: (m['alcoholPercent'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> _toMap(Beverage b) => {
    'id': b.id,
    'name': b.name,
    'category': b.category.name,
    'defaultMl': b.defaultMl,
    if (b.liquidColor != null) 'liquidColor': b.liquidColor!.toARGB32(),
    if (b.hydrationRatio != null) 'hydrationRatio': b.hydrationRatio,
    if (b.templateId != null) 'templateId': b.templateId,
    if (b.animation != null) 'animation': b.animation,
    if (b.volumePreset != null) 'volumePreset': b.volumePreset,
    if (b.containerId != null) 'containerId': b.containerId,
    if (b.calories != null) 'calories': b.calories,
    if (b.caffeineMg != null) 'caffeineMg': b.caffeineMg,
    if (b.alcoholPercent != null) 'alcoholPercent': b.alcoholPercent,
  };

  Future<void> _save() async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.writeAccountSetting(
      AccountSettingKeys.customBeverages,
      state.map(_toMap).toList(),
    );
    // 自定义饮品跟随账号：联网立即上行，换设备登录后可用
    unawaited(SyncService.autoSync(storage));
  }

  /// 新增自定义饮品（由编辑页构建完整对象后传入）。
  /// 新饮品默认不在首页展示（管理页开关默认关闭），由用户手动开启
  Future<void> addCustom(Beverage beverage) async {
    state = [...state, beverage];
    await _save();
    await ref.read(homeDrinksProvider.notifier).registerHidden(beverage.id);
  }

  /// 保存自定义饮品编辑（按 id 整体替换）
  Future<void> updateCustom(Beverage beverage) async {
    state = [
      for (final b in state)
        if (b.id == beverage.id) beverage else b,
    ];
    await _save();
  }

  /// 删除自定义饮品：同步清理首页顺序表 / 隐藏集合里的悬空 id
  Future<void> remove(String id) async {
    state = state.where((b) => b.id != id).toList();
    await _save();
    await ref.read(homeDrinksProvider.notifier).removeId(id);
  }
}

final customBeveragesProvider =
    StateNotifierProvider<CustomBeverageListNotifier, List<Beverage>>((ref) {
      // 会话切换 / 云端偏好更新：按新归属账号的自定义饮品重载
      ref.watch(sessionEpochProvider);
      ref.watch(accountSettingsRevisionProvider);
      return CustomBeverageListNotifier(ref);
    });

// ============================================================
// 首页饮品栏可见性与排序（对标原版：开关控制展示，箭头上下排序）
// ============================================================

/// 首页饮品栏状态：完整顺序 order + 隐藏集合 hidden（水始终显示且不可关）
class HomeDrinksState {
  const HomeDrinksState({this.order = const [], this.hidden = const {}});
  final List<String> order;
  final Set<String> hidden;

  bool isVisible(String id) => id == 'water_pure' || !hidden.contains(id);
}

/// 完整顺序（未登记 id 追加到末尾），供管理页按持久化顺序渲染列表
List<String> orderedAllIds(HomeDrinksState s, Iterable<Beverage> all) {
  final known = s.order.toSet();
  final missing = all.map((b) => b.id).where((id) => !known.contains(id));
  return [...s.order, ...missing];
}

/// 按完整顺序过滤出可见饮品，返回首页栏顺序
List<String> orderedVisibleIds(HomeDrinksState s, Iterable<Beverage> all) =>
    orderedAllIds(s, all).where(s.isVisible).toList();

class HomeDrinksNotifier extends StateNotifier<HomeDrinksState> {
  HomeDrinksNotifier(this.ref) : super(const HomeDrinksState()) {
    _load();
  }

  final Ref ref;

  static const _kOrder = 'home_drink_order';
  static const _kHidden = 'home_drink_hidden';

  /// 上次对齐过的目录顺序签名：后台调整排序后才会覆盖本机顺序
  static const _kOrderSig = 'home_drink_order_sig';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final orderRaw = storage.prefs.getString(_kOrder);
    final hiddenRaw = storage.prefs.getString(_kHidden);
    if (!mounted) return;
    List<String> order = const [];
    Set<String> hidden = <String>{};
    try {
      if (orderRaw != null) {
        order = List<String>.from(jsonDecode(orderRaw) as List);
      }
      if (hiddenRaw != null) {
        hidden = (jsonDecode(hiddenRaw) as List)
            .map((e) => e.toString())
            .toSet();
      }
    } catch (_) {
      // 数据异常时保持默认
    }
    state = HomeDrinksState(order: order, hidden: hidden);
  }

  Future<void> _save() async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_kOrder, jsonEncode(state.order));
    await storage.prefs.setString(_kHidden, jsonEncode(state.hidden.toList()));
  }

  /// 完整顺序（含未登记的新饮品 id）
  List<String> _fullOrder(Iterable<Beverage> all) {
    final known = state.order.toSet();
    final missing = all.map((b) => b.id).where((id) => !known.contains(id));
    return [...state.order, ...missing];
  }

  /// 拖拽排序：把当前可见（筛选后）饮品的新顺序写回完整顺序表，
  /// 未出现在本次筛选中的饮品锚定在原相对位置不动
  Future<void> reorderShown(
    List<String> newShownOrder,
    Iterable<Beverage> all,
  ) async {
    final full = _fullOrder(all);
    final shownSet = newShownOrder.toSet();
    // 未参与排序的饮品按原索引锚定
    final anchored = <String, int>{};
    for (var i = 0; i < full.length; i++) {
      final id = full[i];
      if (!shownSet.contains(id)) anchored[id] = i;
    }
    final result = List<String?>.filled(full.length, null);
    anchored.forEach((id, idx) => result[idx] = id);
    // 空槽位按新顺序回填
    var j = 0;
    for (var i = 0; i < result.length; i++) {
      if (result[i] == null && j < newShownOrder.length) {
        result[i] = newShownOrder[j];
        j++;
      }
    }
    state = HomeDrinksState(
      order: _normalized(result.whereType<String>().toList()),
      hidden: state.hidden,
    );
    await _save();
  }

  /// 顺序规范化：水强制排第一位
  List<String> _normalized(List<String> order) {
    final o = [...order]..remove('water_pure');
    o.insert(0, 'water_pure');
    return o;
  }

  /// 后台调整了饮品排序 / 新增删除：把本机顺序对齐到最新目录顺序
  /// （目录顺序没变时直接返回，不会覆盖用户自己拖拽的顺序；隐藏状态保持不变）
  Future<void> syncCatalogOrder(List<String> libraryIds) async {
    if (libraryIds.isEmpty) return;
    final storage = await ref.read(localStorageProvider.future);
    final sig = jsonEncode(libraryIds);
    if (storage.prefs.getString(_kOrderSig) == sig) return;
    await storage.prefs.setString(_kOrderSig, sig);
    if (!mounted) return;
    state = HomeDrinksState(
      order: _normalized(libraryIds),
      hidden: state.hidden,
    );
    await _save();
  }

  /// 完整顺序 = 已持久化 order + 未登记 id（内置预设 + 当前自定义）按声明序追加。
  /// 全新安装时 order 为空，所有内置饮品仅靠渲染层 missing 兜底展示；
  /// 若开关只对 order 内 id 分区，新开启的饮品会错误地跳到已开启组之上。
  /// 任何变更前先并入，保证分区/排序对全量饮品生效
  List<String> _mergedOrder() {
    final known = state.order.toSet();
    final missing = [
      ...Beverage.presets.map((b) => b.id),
      ...ref.read(customBeveragesProvider).map((b) => b.id),
    ].where((id) => !known.contains(id));
    return [...state.order, ...missing];
  }

  /// 删除饮品时清理顺序表 / 隐藏集合中的悬空 id
  /// （否则 reorderShown 的锚定数组会长期保留幽灵槽位）
  Future<void> removeId(String id) async {
    if (!state.order.contains(id) && !state.hidden.contains(id)) return;
    state = HomeDrinksState(
      order: state.order.where((e) => e != id).toList(),
      hidden: {...state.hidden}..remove(id),
    );
    await _save();
  }

  /// 稳定分区：已开启饮品整体排在已关闭之前（各自保持相对顺序，水固定首位）。
  /// 每次开关后调用，保证「关闭的饮品不会出现在已开启的前面」，
  /// 同时修复历史数据中关闭饮品插在已开启之前的错位
  List<String> _partitioned(List<String> order, Set<String> hidden) {
    final enabled = <String>[];
    final disabled = <String>[];
    for (final id in order) {
      if (id == 'water_pure') continue;
      (hidden.contains(id) ? disabled : enabled).add(id);
    }
    return ['water_pure', ...enabled, ...disabled];
  }

  /// 新饮品登记为默认隐藏（仅进 hidden 集合，管理页开关默认关闭，
  /// 用户开启后经 setVisible 正常进入 order 参与排序）
  Future<void> registerHidden(String id) async {
    if (id == 'water_pure' || state.hidden.contains(id)) return;
    // 未登记饮品并入 order（新饮品入列尾），分区/展示口径一致
    final order = _mergedOrder();
    if (!order.contains(id)) order.add(id);
    state = HomeDrinksState(order: order, hidden: {...state.hidden, id});
    await _save();
  }

  /// 开关首页展示（水不可关闭）。
  /// 业务逻辑闭环：开启 → 自动升到所有已关闭饮品之前（已开启组末位）；
  /// 关闭 → 自动降到列表末尾，不再参与已开启饮品的排序
  Future<void> setVisible(String id, bool visible) async {
    if (id == 'water_pure') return;
    final h = {...state.hidden};
    if (visible) {
      h.remove(id);
    } else {
      h.add(id);
    }
    final order = _mergedOrder();
    order.remove(id);
    order.add(id);
    // 开启 → 落到已开启组末位；关闭 → 落到已关闭组末位。
    // 分区保证已开启整体在已关闭之前（含历史错位修复）
    state = HomeDrinksState(
      order: _normalized(_partitioned(order, h)),
      hidden: h,
    );
    await _save();
  }
}

final homeDrinksProvider =
    StateNotifierProvider<HomeDrinksNotifier, HomeDrinksState>((ref) {
      return HomeDrinksNotifier(ref);
    });
