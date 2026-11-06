import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/characters/current_character_provider.dart';
import '../../features/drink/providers/beverage_catalog_provider.dart';
import '../../features/drink/providers/custom_beverage_provider.dart';
import '../../features/drink/widgets/svg_container.dart';
import '../../features/home/providers/home_providers.dart';
import '../../features/onboarding/widgets/animal_silhouette.dart';
import '../../features/settings/settings_flags.dart';
import '../../features/stats/providers/stats_providers.dart';
import '../../shared/models/beverage.dart';
import '../storage/providers.dart';
import '../time/logical_day.dart';
import 'home_widget_sync.dart';

/// 小组件设置状态（持久化到 SharedPreferences）
class WidgetSettingsState {
  const WidgetSettingsState({
    this.colorIndex = 0,
    this.customColor,
    this.drink1 = 'water_pure',
    this.vol1 = 250,
    this.drink2 = 'milk_juice',
    this.vol2 = 300,
    this.drink3 = 'soda',
    this.vol3 = 330,
    this.colorfulButtons = true,
    this.colorfulCharacter = false,
    this.followDarkMode = false,
    this.streakBadge = true,
  });

  final int colorIndex; // 色板下标，-1 = 自定义色
  final int? customColor; // 自定义色 ARGB（colorIndex == -1 时生效）
  final String drink1;
  final int vol1;
  final String drink2;
  final int vol2;
  final String drink3;
  final int vol3;
  final bool colorfulButtons; // 彩色饮料按钮
  final bool colorfulCharacter; // 彩色字符层
  final bool followDarkMode; // 遵循深色模式规则（系统深色时强制深色底）
  final bool streakBadge; // 连续徽章

  Color get themeColor => colorIndex >= 0
      ? widgetPalette[colorIndex]
      : Color(customColor ?? 0xFFFFFFFF);

  WidgetSettingsState copyWith({
    int? colorIndex,
    int? customColor,
    String? drink1,
    int? vol1,
    String? drink2,
    int? vol2,
    String? drink3,
    int? vol3,
    bool? colorfulButtons,
    bool? colorfulCharacter,
    bool? followDarkMode,
    bool? streakBadge,
  }) =>
      WidgetSettingsState(
        colorIndex: colorIndex ?? this.colorIndex,
        customColor: customColor ?? this.customColor,
        drink1: drink1 ?? this.drink1,
        vol1: vol1 ?? this.vol1,
        drink2: drink2 ?? this.drink2,
        vol2: vol2 ?? this.vol2,
        drink3: drink3 ?? this.drink3,
        vol3: vol3 ?? this.vol3,
        colorfulButtons: colorfulButtons ?? this.colorfulButtons,
        colorfulCharacter: colorfulCharacter ?? this.colorfulCharacter,
        followDarkMode: followDarkMode ?? this.followDarkMode,
        streakBadge: streakBadge ?? this.streakBadge,
      );

  Map<String, dynamic> _toMap() => {
        'colorIndex': colorIndex,
        if (customColor != null) 'customColor': customColor,
        'drink1': drink1, 'vol1': vol1,
        'drink2': drink2, 'vol2': vol2,
        'drink3': drink3, 'vol3': vol3,
        'colorfulButtons': colorfulButtons,
        'colorfulCharacter': colorfulCharacter,
        'followDarkMode': followDarkMode,
        'streakBadge': streakBadge,
      };

  static WidgetSettingsState _fromMap(Map<String, dynamic> m) =>
      WidgetSettingsState(
        colorIndex: (m['colorIndex'] as num?)?.toInt() ?? 0,
        customColor: (m['customColor'] as num?)?.toInt(),
        drink1: m['drink1'] as String? ?? 'water_pure',
        vol1: (m['vol1'] as num?)?.toInt() ?? 250,
        drink2: m['drink2'] as String? ?? 'milk_juice',
        vol2: (m['vol2'] as num?)?.toInt() ?? 300,
        drink3: m['drink3'] as String? ?? 'soda',
        vol3: (m['vol3'] as num?)?.toInt() ?? 330,
        colorfulButtons: m['colorfulButtons'] as bool? ?? true,
        colorfulCharacter: m['colorfulCharacter'] as bool? ?? false,
        followDarkMode: m['followDarkMode'] as bool? ?? false,
        streakBadge: m['streakBadge'] as bool? ?? true,
      );
}

class WidgetSettingsNotifier extends StateNotifier<WidgetSettingsState> {
  WidgetSettingsNotifier(this.ref) : super(const WidgetSettingsState()) {
    loaded = _load();
  }

  final Ref ref;

  static const _kKey = 'widget_settings';

  /// 磁盘加载完成信号：加载完成前 state 是默认值（milk_juice 等），
  /// 冷启动小组件同步必须先等它，否则会把默认饮料格推上桌面
  late final Future<void> loaded;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.prefs.getString(_kKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      state = WidgetSettingsState._fromMap(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // 数据异常保持默认
    }
  }

  Future<void> update(WidgetSettingsState next) async {
    state = next;
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_kKey, jsonEncode(state._toMap()));
    // 设置变化即时刷新桌面小组件（饮料格/主题色/徽章与预览卡保持一致）
    syncWidgetFromSettings(ref.read);
  }

  /// 外部数据（自定义饮品增删改）变更后主动刷新桌面小组件。
  /// 走 notifier 的 ref（Provider 级生命周期），避免页面销毁后
  /// 继续使用已释放的 WidgetRef
  Future<void> refreshWidget() => syncWidgetFromSettings(ref.read);
}

/// 色板（对标原版 5 列 × 4 行）
const List<Color> widgetPalette = [
  Color(0xFFFFFFFF), Color(0xFFF2F2F4), Color(0xFFF5ECDC), Color(0xFF5D4037), Color(0xFF141414),
  Color(0xFFADE1F5), Color(0xFFBBD7F0), Color(0xFFC6E5C5), Color(0xFFA8E6CF), Color(0xFF43A047),
  Color(0xFFFFE45C), Color(0xFFFFB35C), Color(0xFFF48FB1), Color(0xFFE5605C), Color(0xFF8E2436),
  Color(0xFFF8BBD0), Color(0xFFD3C7F2), Color(0xFF7C4DFF), Color(0xFF1E44B8), Color(0xFF64748B),
];

final widgetSettingsProvider =
    StateNotifierProvider<WidgetSettingsNotifier, WidgetSettingsState>((ref) {
  return WidgetSettingsNotifier(ref);
});
// ============================================================
// 桌面小组件数据组装（与预览卡同构）
// ============================================================

/// Provider 泛型读取签名：兼容 Ref.read / WidgetRef.read 的 tear-off
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// 桌面小组件液体波浪动画帧数：一次渲染 16 个相位帧（0..15/16）写盘，
/// 小组件内 ViewFlipper 在 launcher 进程内自动轮播（100ms/帧 ≈ 10fps，
/// 周期 1.6s，与 App 内 1400ms 波浪周期观感一致且平滑）—— 动画不依赖
/// App 存活，退后台/被杀后桌面液体仍持续流动
const int kWidgetFrameCount = 16;

/// 渲染防并发：连续快速录入时合并请求，正在渲染期间的新请求只置
/// pending 标记，结束后补渲一次（避免两个 16 帧循环交错冲突）
bool _framesRendering = false;
bool _framesPending = false;

/// 离屏渲染 8 帧波浪相位角色并推送小组件刷新（与 App 内同款
/// AnimalSilhouette：灰剪影 + 液体填充/达标全彩）。
/// 相位只影响液体波面：0% 灰剪影 / 达标全彩时 8 帧画面一致，
/// 轮播无可见变化、无额外开销
Future<void> renderWidgetCharacterFrames(
  Reader read, {
  Color liquidColor = const Color(0xFF4DB8D8),
}) async {
  if (_framesRendering) {
    _framesPending = true;
    return;
  }
  _framesRendering = true;
  try {
    await _renderFramesOnce(read, liquidColor: liquidColor);
  } finally {
    _framesRendering = false;
  }
  if (_framesPending) {
    _framesPending = false;
    // 补渲必须重读当前设置：渲染期间用户可能改了主题色/彩色字符层，
    // 复用本次入参的 liquidColor 会把旧色帧再推上桌面
    return renderWidgetCharacterFrames(read,
        liquidColor: widgetLiquidColor(read(widgetSettingsProvider)));
  }
}

Future<void> _renderFramesOnce(
  Reader read, {
  required Color liquidColor,
}) async {
  final progress = read(dailyProgressProvider);
  final characterId = read(effectiveCurrentCharacterProvider);
  // 帧签名：同角色 + 同液体色 + 同填充档位（0.5% 步进）+ 同达标态时
  // 16 帧画面完全一致，直接复用已有帧跳过渲染——设置页连续开关
  // （徽章/彩色按钮等不影响画面的项）只剩数据推送，桌面即时刷新
  final sig = '$characterId|${liquidColor.toARGB32().toSigned(32)}|'
      '${(progress.progress.clamp(0.0, 1.0) * 200).round()}|${progress.isComplete}';
  final savedSig = await HomeWidget.getWidgetData<String>('character_frames_sig');
  if (savedSig == sig) return;
  var rendered = 0;
  try {
    for (var i = 0; i < kWidgetFrameCount; i++) {
      final key = 'character_frame_$i';
      var path = await HomeWidget.renderFlutterWidget(
        AnimalSilhouette(
          animalId: characterId,
          fillRatio: progress.progress.clamp(0.0, 1.0),
          accentColor: liquidColor,
          solidFillColor: liquidColor,
          size: 128,
          phase: i / kWidgetFrameCount,
          fullArt: progress.isComplete,
        ),
        key: key,
        // 100dp 角色在 2x 屏上约 260px，2 倍像素足够清晰；16/176 帧都要
        // 逐张渲染，3 倍会让「改液体色」等十几秒才上桌（用户以为没生效）
        logicalSize: const ui.Size(128, 128),
        pixelRatio: 2,
      );
      path ??= await HomeWidget.getWidgetData<String>(key);
      if (path != null && path.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>(key, path);
        rendered++;
        if (i == 0) {
          // 新液体色先上桌：其余 15 帧暂用第 0 帧占位并立即刷新，
          // 之后逐帧回填相位（桌面同一时间只有一种液色，不会闪旧色）
          for (var j = 1; j < kWidgetFrameCount; j++) {
            await HomeWidget.saveWidgetData<String>('character_frame_$j', path);
          }
          await HomeWidget.updateWidget(
            name: 'WaterLlamaWidgetProvider',
            androidName: 'WaterLlamaWidgetProvider',
          );
        }
      }
    }
  } catch (_) {
    // 帧渲染失败静默跳过（下次数据变化同步时自动补上）
  }
  // 签名只在**真的渲出多帧**时才落盘：headless 引擎（小组件后台录入）
  // 无 implicitView，渲染必抛错——此前无条件写签名会让此后所有同步都
  // 命中「签名未变」直接跳过，动画帧永久停在旧画面
  if (rendered >= 2) {
    await HomeWidget.saveWidgetData<String>('character_frames_sig', sig);
  }
  // updateWidget 必须无条件执行：小组件后台录入跑在 headless 引擎里，
  // 帧渲染必然抛错（无 implicitView），若 updateWidget 放在 try 内则
  // 会被跳过——数据虽已写入但桌面 RemoteViews 不重绘，数字永远不更新
  await HomeWidget.updateWidget(
    name: 'WaterLlamaWidgetProvider',
    androidName: 'WaterLlamaWidgetProvider',
  );
  // 等级帧最后维护（数字/动画先行上桌，不被 88 张渲染阻塞；
  // 签名未变秒回，仅首装/角色或液体色变化时重渲）
  try {
    await _renderLevelFrames(read,
        characterId: characterId, liquidColor: liquidColor);
  } catch (_) {
    // 静默：等级帧缺失时原生点按退回旧单帧/无液面更新，下次同步补上
  }
}

/// 静态填充等级帧：0..100% 每 10% 一档 × 16 个波浪相位共 176 张。
/// 原生快捷录入（QuickAddReceiver）跑在 vivo 冻结窗口内、无法执行 Dart
/// 渲染——点按后由原生按新百分比就近取档，16 相位 1:1 写入动画帧槽位，
/// ViewFlipper 以同款 100ms/帧 轮播：动画流畅不中断、液面即时到新档位；
/// 下次 Dart 同步重渲当前填充态动画自动恢复。
/// 角色/液体色不变则复用（签名比对，避免每次同步重渲）
Future<void> _renderLevelFrames(
  Reader read, {
  required String characterId,
  required Color liquidColor,
}) async {
  final sig = '$characterId|${liquidColor.toARGB32().toSigned(32)}|v3';
  final saved = await HomeWidget.getWidgetData<String>('character_levels_sig');
  if (saved == sig) return;
  var rendered = 0;
  for (var pct = 0; pct <= 100; pct += 10) {
    for (var phase = 0; phase < 16; phase++) {
      final key = 'character_level_${pct}_$phase';
      var path = await HomeWidget.renderFlutterWidget(
        AnimalSilhouette(
          animalId: characterId,
          fillRatio: pct / 100,
          accentColor: liquidColor,
          solidFillColor: liquidColor,
          size: 128,
          phase: phase / 16,
          fullArt: pct >= 100,
        ),
        key: key,
        logicalSize: const ui.Size(128, 128),
        pixelRatio: 2, // 与动画帧同倍率：176 帧逐张渲染，3 倍会慢一倍以上
      );
      path ??= await HomeWidget.getWidgetData<String>(key);
      if (path != null && path.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>(key, path);
        rendered++;
      }
    }
  }
  // 与动画帧同理：只有真正渲出绝大部分档位才落签名，否则 headless
  // 引擎下的失败会被签名「记住」导致等级帧永久缺失
  if (rendered >= 160) {
    await HomeWidget.saveWidgetData<String>('character_levels_sig', sig);
  }
}

/// 同步防交错：连续快速改设置时合并请求（渲染/写键交错会产生脏数据）
bool _syncBusy = false;
bool _syncPending = false;

/// 组装小组件数据并刷新：饮料格/主题色/徽章/格底色来自小组件设置
/// （与预览卡同构）；今日合计/目标/连续天数默认读当前状态，
/// 可用参数覆盖（清除数据等重置场景）
///
/// 响应速度关键：数据推送（数字/颜色/饮料格）走同步锁串行执行，
/// 完成后立即 updateWidget 上桌；角色动画帧渲染（16/176 帧，可达数秒）
/// 不占用锁、后台执行——连续调整设置时每次数据都即时上桌，帧由
/// renderWidgetCharacterFrames 自身的 pending 机制合并补渲
Future<void> syncWidgetFromSettings(
  Reader read, {
  int? todayMl,
  int? goalMl,
  int? streakDays,
}) async {
  if (_syncBusy) {
    _syncPending = true;
    return;
  }
  _syncBusy = true;
  try {
    await _syncWidgetFromSettingsOnce(read,
        todayMl: todayMl, goalMl: goalMl, streakDays: streakDays);
  } finally {
    _syncBusy = false;
  }
  unawaited(renderWidgetCharacterFrames(read,
      liquidColor: widgetLiquidColor(read(widgetSettingsProvider))));
  if (_syncPending) {
    _syncPending = false;
    return syncWidgetFromSettings(read);
  }
}

/// 液体填充色：「彩色字符层」开启且有非白主题色时液体跟随主题色，
/// 否则保持品牌青（预览卡与桌面帧同规则）
Color widgetLiquidColor(WidgetSettingsState s) {
  final colorful =
      s.colorIndex != 0 || (s.colorIndex == -1 && s.customColor != null);
  if (s.colorfulCharacter && colorful) return s.themeColor;
  return const Color(0xFF4DB8D8);
}

/// 小组件卡面实际生效底色：预览卡与桌面推送同规则——
/// 「遵循深色模式规则」开启且系统处于深色时**强制深色底**（无论所选
/// 主题色为何），否则选了非白主题色时染主题色、默认白底。
/// 此前只有桌面推送做深色强制、预览卡直接用所选色，系统深色模式下
/// 出现「App 内改颜色、桌面永远不变」的观感错位
Color effectiveWidgetThemeColor(WidgetSettingsState s, {bool? systemDark}) {
  final dark = systemDark ??
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
  if (s.followDarkMode && dark) return const Color(0xFF1C1C22);
  final colorful =
      s.colorIndex != 0 || (s.colorIndex == -1 && s.customColor != null);
  return colorful ? s.themeColor : const Color(0xFFFFFFFF);
}

Future<void> _syncWidgetFromSettingsOnce(
  Reader read, {
  int? todayMl,
  int? goalMl,
  int? streakDays,
}) async {
  try {
    // 冷启动竞态防护：等小组件设置与自定义饮品都从磁盘加载完成再读
    // （此前 1s 定时器同步可能跑在加载前，用默认饮料格覆盖桌面）
    await read(widgetSettingsProvider.notifier).loaded;
    await read(customBeveragesProvider.notifier).loaded;
    // 用户档案加载完成再判初始化态（磁盘异步读，完成前 state 为 null，
    // 不等会把已初始化误判为未初始化 → 小组件被错误锁录入）
    await read(profileProvider.notifier).loaded;
    final s = read(widgetSettingsProvider);
    final progress = read(dailyProgressProvider);
    // 未完成初始化引导（无用户档案）→ 小组件只展示不可录入：
    // 录入数值强制 0 + 原生闸门键 false（详见 syncHomeWidget 注释）
    final recordEnabled = read(profileProvider) != null;
    // 数据文本/饮料格先行推送（不等帧渲染，录入后桌面数字即时更新）
    final slots = [(s.drink1, s.vol1), (s.drink2, s.vol2), (s.drink3, s.vol3)];
    final all = read(beverageLibraryProvider);
    final beverages = [
      for (final (id, _) in slots)
        all.firstWhere((x) => x.id == id, orElse: () => all.first)
    ];
    // 三格图标并行光栅化（命中缓存时近乎零开销）
    final icons =
        await Future.wait([for (final b in beverages) _rasterizeDrinkIcon(b)]);
    final drinks = <WidgetDrinkData>[
      for (var i = 0; i < slots.length; i++)
        WidgetDrinkData(
            ml: slots[i].$2,
            name: beverages[i].name,
            id: slots[i].$1, // 原生点按队列随条目携带，补录不认错饮品
            // 折算后水量：原生点按累加/百分比用它，与 App 内 sumEffective 口径一致
            effectiveMl: beverages[i].effectiveMl(slots[i].$2),
            iconFile: icons[i]),
    ];
    // 连续徽章：streak 已把「今天」纳入当且仅当今天已有记录；原生点按
    // 首笔时按 anchor 判断该 +1 还是断签重置（避免隔天没喝水也照样 +1）
    final streakAsync = read(checkinDaysProvider);
    final streak = streakDays ?? streakAsync.asData?.value ?? 0;
    final today = LogicalDay.today();
    final hasTodayEntry =
        read(todayEntriesProvider).any((e) => LogicalDay.sameDay(e.drankAt, today));
    // streak 还没算出来时不要下发 anchor：否则会把「昨天有记录」误写成
    // 空 → 原生点按把连续天数重置为 1
    final streakKnown = streakDays != null || streakAsync.hasValue;
    final streakAnchor = !streakKnown
        ? null
        : hasTodayEntry
            ? LogicalDay.keyString(today)
            : (streak > 0
                ? LogicalDay.keyString(today.subtract(const Duration(days: 1)))
                : '');
    // 主题色：与预览卡同规则（「遵循深色模式规则」+ 系统深色 → 强制
    // 深色底，详见 effectiveWidgetThemeColor 注释）。恒定有值：默认
    // 白底也显式推白色，行为与 -1 相同且省去空值分支
    final themeColor = effectiveWidgetThemeColor(s);
    await syncHomeWidget(
      todayMl: todayMl ?? progress.totalEffectiveMl,
      goalMl: goalMl ?? progress.goalMl,
      streakDays: streak,
      themeColor: themeColor,
      showStreak: s.streakBadge,
      // 必须转有符号 32 位：白色 0xFFFFFFFF 按无符号存进去原生只会读成
      // -1，而 -1 曾是「默认灰底」哨兵 → 白底主题下彩色按钮永远不生效
      tileColor: s.colorfulButtons ? themeColor.toARGB32().toSigned(32) : -2,
      drinks: drinks,
      recordEnabled: recordEnabled,
      resetMinutes: LogicalDay.resetMinutes,
      streakAnchor: streakAnchor,
      widgetSounds: SettingsFlags.instance.widgetSounds,
    );
    // 角色动画帧由 syncWidgetFromSettings 在数据推送完成后异步补推
    // （不阻塞数据同步锁，见其函数注释）
  } catch (_) {
    // 小组件同步失败不影响主流程
  }
}

/// 饮品图标 PNG 缓存：id → (签名, 文件)。签名 = 容器/插画 id + 液体色，
/// 未变化且文件仍在时直接复用，避免每次同步重复 SVG 解析 + 光栅化
/// （设置页每次调整都要推 3 张图标，无缓存时显著拖慢上桌速度）
final Map<String, (String, File)> _drinkIconCache = {};

/// 光栅化饮品图标为 PNG（RemoteViews 不支持 SVG；规则与预览卡 _drinkThumb
/// 一致：容器剪影按包围盒 92% 居中 + srcIn 染色，预设插画 contain 不染色）
Future<File?> _rasterizeDrinkIcon(Beverage b, {int dim = 96}) async {
  // 云端图标需联网、桌面图标光栅化不动网络：统一回退到分类插画
  final illustId = b.id.startsWith('custom_') ||
          !Beverage.presets.any((p) => p.id == b.id)
      ? (b.templateId ?? Beverage.fallbackIllustration(b.category))
      : b.id;
  final sig = isSvgContainer(b.containerId)
      ? '${b.containerId}|${b.color.toARGB32().toSigned(32)}'
      : 'illust|$illustId';
  final cached = _drinkIconCache[b.id];
  if (cached != null && cached.$1 == sig && cached.$2.existsSync()) {
    return cached.$2;
  }
  try {
    final String assetPath;
    final Color? tint;
    if (isSvgContainer(b.containerId)) {
      assetPath = svgContainerAsset(b.containerId!);
      tint = b.color;
    } else {
      assetPath = 'assets/images/drinks/$illustId.svg';
      tint = null;
    }
    final info = await vg.loadPicture(
      isSvgContainer(b.containerId)
          ? svgContainerLoader(b.containerId!)
          : SvgAssetLoader(assetPath),
      null,
    );
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final box = Offset.zero & Size.square(dim.toDouble());
    if (tint == null) {
      // 预设插画：contain 等比居中
      final s = math.min(dim / info.size.width, dim / info.size.height);
      canvas.translate(
        dim / 2 - info.size.width / 2 * s,
        dim / 2 - info.size.height / 2 * s,
      );
      canvas.scale(s);
      canvas.drawPicture(info.picture);
    } else {
      // 容器剪影：图形包围盒 92% 等比居中（与 SvgContainerIcon 同规则）再整体染色
      // 变换只作用于剪影绘制：srcIn 染色矩形必须在恒等坐标系铺满整个
      // saveLayer（box 尺寸是缩放后的 viewBox 单位，若带着 92% 缩放画，
      // 矩形只落在 viewBox 左上角、剪影完全染不上色 → 黑色剪影）
      canvas.saveLayer(box, ui.Paint());
      canvas.save();
      final m =
          await loadSvgArtMetrics(b.containerId!, info.picture, info.size);
      final bounds = m?.bounds;
      if (bounds == null || bounds.width <= 0 || bounds.height <= 0) {
        canvas.scale(dim / info.size.width, dim / info.size.height);
        canvas.drawPicture(info.picture);
      } else {
        const targetFactor = 0.92;
        final s = math.min(
          dim * targetFactor / bounds.width,
          dim * targetFactor / bounds.height,
        );
        canvas.translate(
          dim / 2 - (bounds.left + bounds.width / 2) * s,
          dim / 2 - (bounds.top + bounds.height / 2) * s,
        );
        canvas.scale(s);
        canvas.drawPicture(info.picture);
      }
      canvas.restore();
      canvas.drawRect(
        box,
        ui.Paint()
          ..color = tint
          ..blendMode = BlendMode.srcIn,
      );
      canvas.restore();
    }
    final image = await rec.endRecording().toImage(dim, dim);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    info.picture.dispose();
    if (data == null) return null;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}home_widget'
        '${Platform.pathSeparator}icon_${b.id}.png');
    await file.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List());
    _drinkIconCache[b.id] = (sig, file);
    return file;
  } catch (_) {
    return null;
  }
}

// StateNotifier 内访问 storage 的辅助（避开构造参数改动）