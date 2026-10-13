import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../shared/models/beverage.dart';

/// 自定义饮品列表（持久化到 SharedPreferences，供首页快捷栏 / 加量页 / 管理页共用）
class CustomBeverageListNotifier extends StateNotifier<List<Beverage>> {
  CustomBeverageListNotifier(this.ref) : super(const []) {
    _load();
  }

  final Ref ref;

  static const _kKey = 'custom_beverages';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => _fromMap(e as Map<String, dynamic>))
          .toList();
      state = list;
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
        if (b.containerId != null) 'containerId': b.containerId,
        if (b.calories != null) 'calories': b.calories,
        if (b.caffeineMg != null) 'caffeineMg': b.caffeineMg,
        if (b.alcoholPercent != null) 'alcoholPercent': b.alcoholPercent,
      };

  Future<void> _save() async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(
      _kKey,
      jsonEncode(state.map(_toMap).toList()),
    );
  }

  /// 新增自定义饮品（由编辑页构建完整对象后传入）
  Future<void> addCustom(Beverage beverage) async {
    state = [...state, beverage];
    await _save();
  }

  /// 保存自定义饮品编辑（按 id 整体替换）
  Future<void> updateCustom(Beverage beverage) async {
    state = [
      for (final b in state)
        if (b.id == beverage.id) beverage else b,
    ];
    await _save();
  }

  /// 删除自定义饮品
  Future<void> remove(String id) async {
    state = state.where((b) => b.id != id).toList();
    await _save();
  }
}

final customBeveragesProvider =
    StateNotifierProvider<CustomBeverageListNotifier, List<Beverage>>((ref) {
  return CustomBeverageListNotifier(ref);
});

/// 完整饮品库 = 内置预设 + 自定义（供加量页按 id 查找）
List<Beverage> allBeverages(List<Beverage> customs) =>
    [...Beverage.presets, ...customs];

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
    await storage.prefs
        .setString(_kHidden, jsonEncode(state.hidden.toList()));
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
    final order = [...state.order];
    if (!order.contains(id)) order.add(id);
    order.remove(id);
    if (visible) {
      // 升序：插入到最后一个已开启饮品之后（水固定首位，从其后面开始找）
      var insertAt = 1;
      for (var i = 1; i < order.length; i++) {
        if (!h.contains(order[i])) insertAt = i + 1;
      }
      order.insert(insertAt, id);
    } else {
      // 降序：掉落末尾
      order.add(id);
    }
    state = HomeDrinksState(order: _normalized(order), hidden: h);
    await _save();
  }
}

final homeDrinksProvider =
    StateNotifierProvider<HomeDrinksNotifier, HomeDrinksState>((ref) {
  return HomeDrinksNotifier(ref);
});
