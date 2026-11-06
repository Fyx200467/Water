import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:water_llama/core/storage/local_storage.dart';
import 'package:water_llama/core/storage/providers.dart';
import 'package:water_llama/features/games/defense/defense_levels.dart';
import 'package:water_llama/features/games/defense/defense_screen.dart';

/// 守卫战页面的冒烟测试：确保画布、HUD、炮塔栏能正常渲染，暂停可切换
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWith((ref) => LocalStorage.init()),
        ],
        child: const MaterialApp(home: DefenseScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('竖屏下页面正常渲染并支持暂停/继续', (tester) async {
    // 按竖屏手机尺寸渲染，顺便兜住布局溢出
    await pumpScreen(tester, const Size(390, 844));

    expect(find.text('吨吨守卫战'), findsOneWidget);
    expect(find.text('第 1 关'), findsOneWidget);
    expect(find.text('水杯水量'), findsOneWidget);
    expect(find.text('水滴币'), findsOneWidget);
    expect(find.text('波次'), findsOneWidget);
    expect(find.text('击退怪兽'), findsOneWidget);
    // 底部图例（摆放说明，不再需要先选中塔）
    expect(find.text('水滴塔 40'), findsOneWidget);
    expect(find.text('茶杯炮 60'), findsOneWidget);
    expect(find.text('冰饮塔 50'), findsOneWidget);
    expect(find.text('点虚线炮位选塔建造 · 点已建炮塔升级 / 出售'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(find.text('已暂停'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('已暂停'), findsNothing);
    expect(tester.takeException(), isNull);

    // 关卡选择：只有第 1 关可玩，其余锁定
    await tester.tap(find.text('第 1 关'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('选择关卡'), findsOneWidget);
    expect(find.text('第 1 关 · 清凉小径'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('布阵阶段点出口「开始」后才出怪', (tester) async {
    await pumpScreen(tester, const Size(390, 844));

    // 布阵阶段：提示文字 + 出口开始标记都在
    expect(find.text('布阵阶段 · 点出口的「开始」再召唤怪兽'), findsOneWidget);
    expect(find.byKey(const ValueKey('defense-start')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('defense-start')));
    await tester.pump(const Duration(milliseconds: 200));

    // 点完后标记消失，进入出怪阶段
    expect(find.byKey(const ValueKey('defense-start')), findsNothing);
    expect(find.text('布阵阶段 · 点出口的「开始」再召唤怪兽'), findsNothing);
    expect(find.textContaining('正在冲向水杯'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点炮位原地弹菜单建塔，点塔原地升级/出售（不暂停）', (tester) async {
    await pumpScreen(tester, const Size(390, 844));

    final board = find.byKey(const ValueKey('defense-board'));
    expect(board, findsOneWidget);
    final rect = tester.getRect(board);
    final cell = rect.width / 9;
    final slot = defenseLevelFor(1).slots.first;
    final slotPos = rect.topLeft +
        Offset((slot.col + 0.5) * cell, (slot.row + 0.5) * cell);

    // 1. 点空炮位 → 炮位旁原地弹出选塔菜单（底部不弹面板、不暂停）
    await tester.tapAt(slotPos);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('选择炮塔'), findsOneWidget);
    expect(find.text('水滴塔'), findsOneWidget);
    expect(find.text('茶杯炮'), findsOneWidget);
    expect(find.text('冰饮塔'), findsOneWidget);
    expect(find.text('已暂停'), findsNothing);

    // 2. 选中水滴塔 → 直接建在刚才点中的炮位
    await tester.tap(find.text('水滴塔'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('选择炮塔'), findsNothing);

    // 3. 再点这座塔 → 原地升级 / 出售
    await tester.tapAt(slotPos);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('水滴塔 · Lv1'), findsOneWidget);
    expect(find.text('升级 48'), findsOneWidget);
    expect(find.text('出售 +28'), findsOneWidget);
    expect(find.text('已暂停'), findsNothing);

    await tester.tap(find.text('升级 48'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('水滴塔 · Lv2'), findsOneWidget);
    expect(find.text('出售 +62'), findsOneWidget);

    await tester.tap(find.text('出售 +62'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('水滴塔 · Lv2'), findsNothing);
    expect(find.text('已出售，返还 62 水滴币'), findsOneWidget);

    // 4. 炮位恢复成空的，可以重新建塔
    await tester.tapAt(slotPos);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('选择炮塔'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
