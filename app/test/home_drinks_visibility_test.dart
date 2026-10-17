import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:water_llama/core/storage/local_storage.dart';
import 'package:water_llama/core/storage/providers.dart';
import 'package:water_llama/features/drink/providers/custom_beverage_provider.dart';

/// 首页饮品栏可见性/排序逻辑回归测试
///
/// 两个历史 bug：
/// 1. 空 order 首次开启时 insert 越界静默崩溃（开关「点不动」）
/// 2. 全新安装时 order 为空，内置饮品仅靠渲染层 missing 兜底展示，
///    setVisible 只对 order 内 id 分区 → 新开启的饮品跳到最上方、
///    关闭后也不掉回已开启组之下（真机首装实测）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer buildContainer() {
    final container = ProviderContainer(overrides: [
      localStorageProvider.overrideWith((ref) => LocalStorage.init()),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// 分区不变量：任意已开启饮品不得出现在任意已关闭饮品之后
  void expectPartitioned(List<String> order, Set<String> hidden) {
    var seenDisabled = false;
    for (final id in order) {
      if (id == 'water_pure') continue;
      if (hidden.contains(id)) {
        seenDisabled = true;
      } else {
        expect(seenDisabled, isFalse,
            reason: '已开启的 $id 出现在已关闭饮品之后: $order');
      }
    }
  }

  test('空 order 首次开启自定义饮品：并入全量后分区，不再越界崩溃', () async {
    SharedPreferences.setMockInitialValues({
      'home_drink_hidden': '["custom_1"]',
    });
    final container = buildContainer();
    final notifier = container.read(homeDrinksProvider.notifier);
    await Future<void>.delayed(Duration.zero); // 等 _load 完成
    expect(container.read(homeDrinksProvider).order, isEmpty);

    await notifier.setVisible('custom_1', true);
    final s = container.read(homeDrinksProvider);
    expect(s.order.first, 'water_pure');
    expect(s.order.contains('custom_1'), isTrue);
    expect(s.hidden, isEmpty);
    expect(s.isVisible('custom_1'), isTrue);
    expectPartitioned(s.order, s.hidden);
  });

  test('关闭饮品排在已开启之前时：开启任意饮品整体修复错位', () async {
    // 模拟脏数据：关闭的奶茶/红酒/222 排在已开启的啤酒/111 之前
    SharedPreferences.setMockInitialValues({
      'home_drink_order':
          '["water_pure","tea","wine","custom_222","beer","custom_111"]',
      'home_drink_hidden': '["tea","wine","custom_222"]',
    });
    final container = buildContainer();
    final notifier = container.read(homeDrinksProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    await notifier.setVisible('custom_222', true);
    final s = container.read(homeDrinksProvider);
    final o = s.order;
    // 开启 222：升入已开启组，且仍在关闭组（tea/wine）之前
    expect(o.indexOf('beer') < o.indexOf('custom_111'), isTrue);
    expect(o.indexOf('custom_111') < o.indexOf('custom_222'), isTrue);
    expect(o.indexOf('custom_222') < o.indexOf('tea'), isTrue);
    expect(o.indexOf('tea') < o.indexOf('wine'), isTrue);
    expectPartitioned(o, s.hidden);
  });

  test('关闭饮品：加入 hidden 并掉到已开启组之下', () async {
    SharedPreferences.setMockInitialValues({
      'home_drink_order': '["water_pure","custom_1","tea"]',
      'home_drink_hidden': '[]',
    });
    final container = buildContainer();
    final notifier = container.read(homeDrinksProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    await notifier.setVisible('custom_1', false);
    final s = container.read(homeDrinksProvider);
    expect(s.order.last, 'custom_1');
    expect(s.hidden, ['custom_1']);
    expect(s.isVisible('custom_1'), isFalse);
    expectPartitioned(s.order, s.hidden);
  });

  test('全新安装（order 空）：开启后再关闭自定义饮品，不掉到已开启组之上', () async {
    // 复刻真机首装场景：order 空，预设饮品全部走渲染层 missing 兜底
    SharedPreferences.setMockInitialValues({
      'home_drink_order': '[]',
      'home_drink_hidden': '[]',
    });
    final container = buildContainer();
    final notifier = container.read(homeDrinksProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    // 添加自定义饮品 → 登记默认隐藏（此时全部预设并入 order，饮品在列尾）
    await notifier.registerHidden('custom_juzi');
    var s = container.read(homeDrinksProvider);
    expect(s.order.last, 'custom_juzi');
    expect(s.isVisible('custom_juzi'), isFalse);

    // 开启：升入已开启组末位（所有已开启预设之后），而不是跳到最上方
    await notifier.setVisible('custom_juzi', true);
    s = container.read(homeDrinksProvider);
    expect(s.isVisible('custom_juzi'), isTrue);
    expect(s.order.indexOf('custom_juzi'), greaterThan(s.order.indexOf('tea')));
    expectPartitioned(s.order, s.hidden);

    // 关闭：掉到已开启组之下（列表末尾）
    await notifier.setVisible('custom_juzi', false);
    s = container.read(homeDrinksProvider);
    expect(s.isVisible('custom_juzi'), isFalse);
    expect(s.order.last, 'custom_juzi');
    expectPartitioned(s.order, s.hidden);
  });
}
