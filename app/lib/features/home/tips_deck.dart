import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/sync/sync_api.dart';
import 'tips_all_screen.dart';

/// 已读（完成）贴士集合——全局共享：首页牌堆「✓ N/3」与查看全部页
/// 各分组「N/M」计数实时联动。key = 卡片标题（文案唯一）。
final ValueNotifier<Set<String>> tipsRead = ValueNotifier(const {});

bool _tipsReadLoaded = false;

/// 启动时载入持久化的已完成贴士（幂等）
Future<void> ensureTipsReadLoaded() async {
  if (_tipsReadLoaded) return;
  _tipsReadLoaded = true;
  final prefs = await SharedPreferences.getInstance();
  tipsRead.value = (prefs.getStringList('tips_read') ?? const []).toSet();
}

/// 标记一条贴士为已完成（点击卡片）：更新通知 + 持久化
Future<void> markTipRead(TipCardData tip) async {
  if (tipsRead.value.contains(tip.title)) return;
  tipsRead.value = {...tipsRead.value, tip.title};
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('tips_read', tipsRead.value.toList());
}

/// 「今日小贴士」卡片牌堆（对标原版：限时挑战模块下方，三卡层叠可左右滑动）
///
/// 交互（对标原版录屏）：拖动顶层卡片向左/向右，跟手平移+轻微旋转；
/// 松手超过阈值（位移 28% 卡宽 或 速度 700）则卡片加速飞出屏幕并压到
/// 牌堆最底层，后方卡片依次上浮补位（循环轮换）；未达阈值则回弹归位。
/// 后方卡片略窄且下沉（底边露出窄条），上浮过程随拖动进度实时跟手。
///
/// 卡片来源：三张堆叠卡 = 从 kTipPool（查看全部页全量主题卡池）随机抽 3。
///
/// 排版预留：卡面 = 底层插画区（整卡铺满，后续放后台图）+ 顶层左下角
/// 文案。文案永远浮在图片上层，后台上传图片与文案不会产生排版异常。
///
/// 下方为「✓ 0/3 今日小贴士 / 查看全部」计数行。
class TipsDeckModule extends StatefulWidget {
  const TipsDeckModule({super.key});

  @override
  State<TipsDeckModule> createState() => _TipsDeckModuleState();
}

class _TipsDeckModuleState extends State<TipsDeckModule> {
  /// 三张堆叠卡 = 从后台下发的卡池（未配置时用内置卡池）随机抽 3
  late List<TipCardData> _deck = pickRandomTips(3, pool: TipStore.pool.value);

  @override
  void initState() {
    super.initState();
    ensureTipsReadLoaded();
    TipStore.pool.addListener(_onPoolChanged);
  }

  void _onPoolChanged() {
    if (!mounted) return;
    setState(() => _deck = pickRandomTips(3, pool: TipStore.pool.value));
  }

  @override
  void dispose() {
    TipStore.pool.removeListener(_onPoolChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 30),
      child: Column(
        children: [
          TipsDeck(cards: _deck),
          const SizedBox(height: 18),
          _TipsCounterRow(cards: _deck),
        ],
      ),
    );
  }
}

/// 贴士分组常量（const 上下文不能做 List 索引，先声明顶层常量再引用）
const TipGroup gHydration = TipGroup('进水量', Color(0xFF2BB3CE), 9);
const TipGroup gLifehacks = TipGroup('生活小窍门', Color(0xFF9B5DE2), 12);
const TipGroup gDrinks = TipGroup('美味饮品', Color(0xFF2C6FE8), 6);
const TipGroup gHealth = TipGroup('健康益处', Color(0xFF19B8A6), 17);
const TipGroup gGeneral = TipGroup('通用', Color(0xFFF5B301), 8);

/// 贴士分组（对标原版「查看全部」页：胶囊计数 + 分类标题色）
class TipGroup {
  const TipGroup(this.name, this.color, this.total);

  final String name;
  final Color color;

  /// 该组全量卡片数（对标原版：9/12/6/17/8，后续后台上传补齐）
  final int total;

  static const List<TipGroup> all = [
    gHydration,
    gLifehacks,
    gDrinks,
    gHealth,
    gGeneral,
  ];
}

/// 单张贴士卡数据：后台可配置文案、配色与插画，未配置插画时显示纯色底
class TipCardData {
  const TipCardData({
    required this.group,
    required this.bg,
    required this.fg,
    required this.title,
    this.image,
    this.imageUrl,
  });

  final TipGroup group;
  final Color bg;
  final Color fg;
  final String title;

  /// 安装包内置插画资产路径（null 时显示纯色底）
  final String? image;

  /// 后台下发的云端插画地址（优先于内置资产）
  final String? imageUrl;

  /// 后台下发的卡片 → 本地模型
  factory TipCardData.fromJson(Map<String, dynamic> j) {
    final group = tipGroupByCode(j['groupCode'] as String?);
    final bg = _parseHexColor(j['bgColor'] as String?) ??
        group.color.withValues(alpha: 0.16);
    final fg = _parseHexColor(j['fgColor'] as String?) ?? group.color;
    final url = (j['imageUrl'] as String?)?.trim();
    return TipCardData(
      group: group,
      bg: bg,
      fg: fg,
      title: (j['title'] as String?) ?? '',
      imageUrl: (url == null || url.isEmpty) ? null : url,
    );
  }
}

/// 分组 code ↔ 客户端分组（与后台 tips.group_code 一致）
TipGroup tipGroupByCode(String? code) {
  switch (code) {
    case 'hydration':
      return gHydration;
    case 'lifehacks':
      return gLifehacks;
    case 'drinks':
      return gDrinks;
    case 'health':
      return gHealth;
    default:
      return gGeneral;
  }
}

Color? _parseHexColor(String? hex) {
  final v = (hex ?? '').trim().replaceFirst('#', '');
  if (v.length != 6) return null;
  final n = int.tryParse(v, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}

/// 贴士卡池：启动时读缓存，联网后与后台对齐；后台没配置时保留内置卡池
class TipStore {
  static const _kCache = 'tips_cache_v1';

  static final ValueNotifier<List<TipCardData>> pool =
      ValueNotifier<List<TipCardData>>(kTipPool);

  /// 读回上次同步结果（离线优先）
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCache);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => TipCardData.fromJson(e as Map<String, dynamic>))
          .where((t) => t.title.isNotEmpty)
          .toList();
      if (list.isNotEmpty) pool.value = list;
    } catch (_) {
      // 缓存损坏时继续用内置卡池
    }
  }

  /// 拉取后台贴士目录；空数组视为「未配置」，继续用内置卡池
  static Future<bool> sync() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(
        Uri.parse('${SyncApi.baseUrl}/v1/catalog/tips'),
      );
      final res = await req.close();
      if (res.statusCode != 200) return false;
      final text = await res.transform(utf8.decoder).join();
      final data = jsonDecode(text) as List;
      final list = data
          .map((e) => TipCardData.fromJson(e as Map<String, dynamic>))
          .where((t) => t.title.isNotEmpty)
          .toList();
      if (list.isEmpty) return false;
      pool.value = list;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCache, text);
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}

/// 全量主题卡池（文案先写死对标原版，后续接管理端上传）
const List<TipCardData> kTipPool = [
  // 进水量
  TipCardData(
      group: gHydration,
      bg: Color(0xFFD9E9F7),
      fg: Color(0xFF2C6FE8),
      title: '了解各种风险，\n打赢补水战！',
      image: 'assets/images/tips/tip_hydration_risks.png'),
  TipCardData(
      group: gHydration,
      bg: Color(0xFFF9D9E4),
      fg: Color(0xFFD6547E),
      title: '充分补水，\n远离麻痹！'),
  TipCardData(
      group: gHydration,
      bg: Color(0xFFFBDEE7),
      fg: Color(0xFFD6547E),
      title: '缺水警告！',
      image: 'assets/images/tips/tip_hydration_warning.png'),
  TipCardData(
      group: gHydration,
      bg: Color(0xFFD2E7F8),
      fg: Color(0xFF2C6FE8),
      title: '导致脱水的元凶',
      image: 'assets/images/tips/tip_dehydration_culprits.png'),
  TipCardData(
      group: gHydration,
      bg: Color(0xFFFADAE1),
      fg: Color(0xFFD6547E),
      title: '身体需要补水的迹象',
      image: 'assets/images/tips/tip_dehydration_signs.png'),
  TipCardData(
      group: gHydration,
      bg: Color(0xFFF0EADB),
      fg: Color(0xFF8A7A4E),
      title: '想要了解补水真相\n吗？'),
  // 生活小窍门
  TipCardData(
      group: gLifehacks,
      bg: Color(0xFFC9EDE4),
      fg: Color(0xFF1F9E87),
      title: '潜心减肥！',
      image: 'assets/images/tips/tip_diet.png'),
  TipCardData(
      group: gLifehacks,
      bg: Color(0xFFE9EDB2),
      fg: Color(0xFF3F7D4E),
      title: '在家办公也别忘了\n补水哦！',
      image: 'assets/images/tips/tip_wfh_hydrate.png'),
  TipCardData(
      group: gLifehacks,
      bg: Color(0xFFF7D9DC),
      fg: Color(0xFFD6547E),
      title: '以水和茶相伴的\n夜晚时光'),
  TipCardData(
      group: gLifehacks,
      bg: Color(0xFFF3E9A6),
      fg: Color(0xFFC07A2B),
      title: '远离酷暑，保持清凉'),
  TipCardData(
      group: gLifehacks,
      bg: Color(0xFFF9D8DF),
      fg: Color(0xFFD6547E),
      title: '旅行时记得\n充分补水！'),
  // 美味饮品
  TipCardData(
      group: gDrinks,
      bg: Color(0xFFD5E8C2),
      fg: Color(0xFF3F7D4E),
      title: '补水美食',
      image: 'assets/images/tips/tip_food_hydration.png'),
  TipCardData(
      group: gDrinks,
      bg: Color(0xFFCEEBc9),
      fg: Color(0xFF3F7D4E),
      title: '热带饮品：椰汁',
      image: 'assets/images/tips/tip_coconut.png'),
  TipCardData(
      group: gDrinks,
      bg: Color(0xFFDAEDCB),
      fg: Color(0xFF3F7D4E),
      title: '黄瓜水的秘密',
      image: 'assets/images/tips/tip_cucumber_water.png'),
  TipCardData(
      group: gDrinks,
      bg: Color(0xFFEAEDB4),
      fg: Color(0xFF3F7D4E),
      title: '走近活力四射的\n柠檬水',
      image: 'assets/images/tips/tip_lemonade.png'),
  TipCardData(
      group: gDrinks,
      bg: Color(0xFFF6E3B8),
      fg: Color(0xFFC07A2B),
      title: '补水食物知多少',
      image: 'assets/images/tips/tip_hydrating_foods.png'),
  TipCardData(
      group: gDrinks,
      bg: Color(0xFFD0E4F6),
      fg: Color(0xFF2C6FE8),
      title: '隐形的水分来源',
      image: 'assets/images/tips/tip_hidden_water.png'),
  // 健康益处
  TipCardData(
      group: gHealth,
      bg: Color(0xFFE0E9AE),
      fg: Color(0xFF3F7D4E),
      title: '拥有闪亮双眸！',
      image: 'assets/images/tips/tip_bright_eyes.png'),
  TipCardData(
      group: gHealth,
      bg: Color(0xFFF9D8DE),
      fg: Color(0xFFD6547E),
      title: '再见，便秘！',
      image: 'assets/images/tips/tip_bye_constipation.png'),
  TipCardData(
      group: gHealth,
      bg: Color(0xFFF7DAE3),
      fg: Color(0xFFD6547E),
      title: '安然入梦',
      image: 'assets/images/tips/tip_sleep.png'),
  TipCardData(
      group: gHealth,
      bg: Color(0xFFF0DAEF),
      fg: Color(0xFF9B5DE2),
      title: '逃离甜食：\n无糖小贴士',
      image: 'assets/images/tips/tip_no_sugar.png'),
  TipCardData(
      group: gHealth,
      bg: Color(0xFFD9ECC8),
      fg: Color(0xFF3F7D4E),
      title: '充分补水，让肌肤\n绽放光彩！',
      image: 'assets/images/tips/tip_glowing_skin.png'),
  // 通用
  TipCardData(
      group: gGeneral,
      bg: Color(0xFFD0E7F4),
      fg: Color(0xFF2C6FE8),
      title: '让我们破除关于补\n水的一些误区！'),
  TipCardData(
      group: gGeneral,
      bg: Color(0xFFF9DAE1),
      fg: Color(0xFFD6547E),
      title: '坚持每日饮水，\n乐享美好生活',
      image: 'assets/images/tips/tip_daily_water.png'),
  TipCardData(
      group: gGeneral,
      bg: Color(0xFFF6D8E5),
      fg: Color(0xFFD6547E),
      title: '水之炼金术大揭秘',
      image: 'assets/images/tips/tip_water_alchemy.png'),
  TipCardData(
      group: gGeneral,
      bg: Color(0xFFE7DAF2),
      fg: Color(0xFF9B5DE2),
      title: '打破误区',
      image: 'assets/images/tips/tip_break_myths.png'),
  TipCardData(
      group: gGeneral,
      bg: Color(0xFFFBEBD2),
      fg: Color(0xFFC07A2B),
      title: '喝水也要讲究时机！'),
];

/// 从卡池随机抽 n 张不重复卡（首页牌堆用；默认内置池，可传后台目录）
List<TipCardData> pickRandomTips(int n, {List<TipCardData>? pool}) {
  final src = List.of(pool ?? kTipPool)..shuffle(Random());
  return src.take(n).toList();
}

/// 贴士卡面（堆叠卡与查看全部页共用）：
/// 底层插画区铺满整卡（后续放后台图），顶层左下角文案叠加——
/// 图片与文案均后续可换，排版不受影响。
class TipCardFace extends StatelessWidget {
  const TipCardFace({
    super.key,
    required this.data,
    required this.width,
    required this.height,
    this.titleSize = 24,
    this.done = false,
  });

  final TipCardData data;
  final double width;
  final double height;

  /// 文案字号：堆叠卡 24，查看全部页按缩放比例传入
  final double titleSize;

  /// 已完成：右上角绿色对勾徽章
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: data.bg,
        borderRadius: BorderRadius.circular(32),
      ),
      // Stack：底层插画区（占位=纯色底，后台图上传后铺满此层）
      // + 顶层左下文案（文案永远在图片顶层）
      child: Stack(
        children: [
          // 插画层：铺满整卡（BoxFit.cover 等比铺满+居中裁剪，尺寸不匹配自动裁边）
          Positioned.fill(
            child: data.imageUrl != null
                ? Image.network(
                    data.imageUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) => const SizedBox.expand(),
                  )
                : data.image != null
                    ? Image.asset(
                        data.image!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      )
                    : const SizedBox.expand(),
          ),
          // 文案层：左下角，最多 3 行防长文案溢出
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: Text(
              data.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: data.fg,
                fontSize: titleSize,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
          // 已完成徽章：右上角绿底白对勾
          if (done)
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: Color(0xFF23A06A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 位姿（平移 / 旋转 / 横向缩放），用于牌堆插值动画
class _Pose {
  const _Pose({
    required this.dx,
    required this.dy,
    required this.rot,
    required this.sx,
  });

  final double dx;
  final double dy;
  final double rot;
  final double sx;

  static _Pose lerp(_Pose a, _Pose b, double t) => _Pose(
        dx: a.dx + (b.dx - a.dx) * t,
        dy: a.dy + (b.dy - a.dy) * t,
        rot: a.rot + (b.rot - a.rot) * t,
        sx: a.sx + (b.sx - a.sx) * t,
      );
}

class TipsDeck extends StatefulWidget {
  const TipsDeck({super.key, required this.cards});

  /// 牌堆三张卡（由 TipsDeckModule 随机抽出后传入，计数行共享同一份）
  final List<TipCardData> cards;

  @override
  State<TipsDeck> createState() => _TipsDeckState();
}

class _TipsDeckState extends State<TipsDeck> with TickerProviderStateMixin {
  /// 后方卡片下沉量与横向缩放（index 1/2）：底边露出窄条、略窄于顶层卡
  static const _backDy = [0.0, 12.0, 24.0];
  static const _backSx = [1.0, 0.96, 0.92];

  /// 飞出/归位判定：位移超 28% 卡宽 或 速度超 700
  static const _commitDistanceRatio = 0.28;
  static const _commitVelocity = 700.0;

  late List<TipCardData> _deck;
  final ValueNotifier<double> _dragX = ValueNotifier(0);

  late final AnimationController _flyCtrl; // 飞出屏幕
  late final AnimationController _settleCtrl; // 重排后各卡滑到新位
  late final AnimationController _springCtrl; // 未达阈值回弹

  bool _flying = false;
  bool _springing = false;
  double _exitSign = 1;
  double _springFrom = 0;
  double _cardW = 0;

  /// 松手瞬间的上浮进度（第二张卡从该进度连续补满，避免跳满位突跳）
  double _floatStartP = 0;

  /// 重排瞬间各卡的真实位姿快照（settle 动画起点，避免新顶卡跳回沉底再上浮的震颤）
  Map<TipCardData, _Pose> _settleFrom = const {};

  @override
  void initState() {
    super.initState();
    _deck = List.of(widget.cards);
    _flyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _settleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _springCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _flyCtrl.addListener(() => setState(() {}));
    _settleCtrl.addListener(() => setState(() {}));
    _springCtrl.addListener(() => setState(() {}));
    _dragX.addListener(() => setState(() {}));
    _flyCtrl.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      setState(() {
        // 飞出完成瞬间各卡位姿是确定的（t=1）：飞行卡=飞出屏幕位、
        // 第二张=已补满到顶层位、第三张=原位。以此作为 settle 起点，
        // 新顶卡从当前浮起位平滑落定，不再跳回沉底再上浮（消除震颤）
        _settleFrom = {
          _deck[0]: _exitPose(_cardW),
          if (_deck.length > 1) _deck[1]: _pos(0),
          if (_deck.length > 2) _deck[2]: _pos(2),
        };
        final flown = _deck.removeAt(0);
        _deck.add(flown);
        _flying = false;
        _dragX.value = 0;
      });
      _settleCtrl.forward(from: 0);
    });
    _springCtrl.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      setState(() {
        _springing = false;
        _dragX.value = 0;
      });
    });
    _settleCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _settleFrom = const {};
      }
    });
  }

  @override
  void dispose() {
    _dragX.dispose();
    _flyCtrl.dispose();
    _settleCtrl.dispose();
    _springCtrl.dispose();
    super.dispose();
  }

  // ---------- 手势 ----------

  void _onDragUpdate(DragUpdateDetails d) {
    _dragX.value += d.delta.dx;
  }

  void _onDragEnd(DragEndDetails d) {
    final dx = _dragX.value;
    final v = d.velocity.pixelsPerSecond.dx;
    final commit = dx.abs() > _cardW * _commitDistanceRatio ||
        v.abs() > _commitVelocity;
    if (commit) {
      _exitSign = dx.abs() > 8
          ? (dx > 0 ? 1.0 : -1.0)
          : (v >= 0 ? 1.0 : -1.0);
      // 记录松手瞬间第二张卡的上浮进度，飞出期间从该进度连续补满
      _floatStartP =
          (_dragX.value.abs() / (_cardW * 0.55)).clamp(0.0, 1.0);
      _flying = true;
      _flyCtrl.forward(from: 0);
    } else {
      _springFrom = dx;
      _springing = true;
      _springCtrl.forward(from: 0);
    }
  }

  // ---------- 位姿计算 ----------

  _Pose _pos(int k) =>
      _Pose(dx: 0, dy: _backDy[k], rot: 0, sx: _backSx[k]);

  _Pose _dragPose(double dx, double w) => _Pose(
        dx: dx,
        dy: 0,
        rot: dx / w * 0.35,
        sx: 1,
      );

  _Pose _exitPose(double w) => _Pose(
        dx: _exitSign * (w + 120),
        dy: 0,
        rot: _exitSign * 0.32,
        sx: 1,
      );

  /// 各卡当前位姿
  _Pose _poseFor(TipCardData data, int i, double w) {
    // 重排归位：从快照位姿平滑滑到新位姿（起点=重排瞬间的真实位姿，无跳变）
    if (_settleCtrl.isAnimating) {
      final t = Curves.easeOutCubic.transform(_settleCtrl.value);
      final from = _settleFrom[data] ?? _pos(i);
      return _Pose.lerp(from, _pos(i), t);
    }
    if (i == 0) {
      if (_flying) {
        // 顶层卡：从拖拽位姿加速飞出屏幕
        final t = Curves.easeInCubic.transform(_flyCtrl.value);
        return _Pose.lerp(_dragPose(_dragX.value, w), _exitPose(w), t);
      }
      if (_springing) {
        // 回弹：拖拽位姿 → 归位
        final t = Curves.easeOutCubic.transform(_springCtrl.value);
        return _dragPose(_springFrom + (0 - _springFrom) * t, w);
      }
      return _dragPose(_dragX.value, w);
    }
    if (i == 1) {
      // 后方第一张：随拖动进度实时上浮跟手；飞出期间从松手时的
      // 实际进度连续补满到顶层位（不再直接跳满位）
      double p;
      if (_flying) {
        p = _floatStartP +
            (1 - _floatStartP) *
                Curves.easeInCubic.transform(_flyCtrl.value);
      } else {
        final topDx = _springing
            ? _springFrom *
                (1 - Curves.easeOutCubic.transform(_springCtrl.value))
            : _dragX.value;
        p = (topDx.abs() / (w * 0.55)).clamp(0.0, 1.0);
      }
      return _Pose.lerp(_pos(1), _pos(0), p);
    }
    return _pos(2);
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        // 与限时挑战卡视觉同宽：挑战面板 = margin 26×2 后再 Transform.scale(0.9)，
        // 牌堆卡布局宽同步减 52，缩放后视觉宽与酒红卡完全一致
        final contentW = w - 52;
        _cardW = contentW;
        final cardH = contentW / 0.78;
        return SizedBox(
          // 外层高度按 0.9 缩放补偿，避免下方计数行出现大空隙
          height: (cardH + _backDy.last) * 0.9,
          child: Transform.scale(
            scale: 0.9,
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: cardH + _backDy.last,
              width: w,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // 从最底层往上绘制，保证顶层卡接收手势
                  for (var i = _deck.length - 1; i >= 0; i--)
                    _buildCard(_deck[i], i, contentW, cardH),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(TipCardData data, int i, double w, double cardH) {
    final pose = _poseFor(data, i, w);
    Widget card = Transform.translate(
      offset: Offset(pose.dx, pose.dy),
      child: Transform.rotate(
        angle: pose.rot,
        child: Transform.scale(
          scaleX: pose.sx,
          scaleY: 1,
          // 已完成徽章实时联动（点击卡片即标记完成）
          child: ValueListenableBuilder<Set<String>>(
            valueListenable: tipsRead,
            builder: (_, read, __) => TipCardFace(
              data: data,
              width: w,
              height: cardH,
              done: read.contains(data.title),
            ),
          ),
        ),
      ),
    );
    // 仅顶层卡（非飞出中）响应水平拖拽；点按=标记该条完成
    if (i == 0 && !_flying) {
      card = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => markTipRead(data),
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: card,
      );
    }
    return card;
  }
}

/// 底部计数行：✓ N/3 青色胶囊 + 「今日小贴士」+「查看全部」
/// （N = 当前牌堆三张卡中已完成的条数，点击卡片即+1，实时联动）
class _TipsCounterRow extends StatelessWidget {
  const _TipsCounterRow({required this.cards});

  final List<TipCardData> cards;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: tipsRead,
      builder: (context, read, _) {
        final done = cards.where((c) => read.contains(c.title)).length;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF2BB3CE),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '$done/${cards.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '今日小贴士',
                  style: TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            GestureDetector(
              // 跳转查看全部页（从底部滑入，同挑战详情转场）
              onTap: () => Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const TipsAllScreen(),
                  transitionsBuilder: (_, animation, __, child) {
                    final offset = Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                          parent: animation, curve: Curves.easeOutCubic),
                    );
                    return SlideTransition(position: offset, child: child);
                  },
                  transitionDuration: const Duration(milliseconds: 350),
                ),
              ),
              child: const Text(
                '查看全部',
                style: TextStyle(
                  color: Color(0xFF2BB3CE),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
        );
      },
    );
  }
}
