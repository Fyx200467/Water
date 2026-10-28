import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'character_art.dart';
import 'character_catalog.dart';
import 'character_data.dart';
import 'current_character_provider.dart';
import '../membership/membership_provider.dart';
import '../membership/membership_screen.dart';
import '../settings/widget_settings_screen.dart';

/// 角色展示页：从底部滑出的独立全屏页面（不可拖拽关闭，只能点 X 返回）
///
/// 头部固定（随机按钮 + 关闭 + 当前角色卡片），
/// 下方 12 个分类网格上下滚动，每个卡片用 CharacterArt 渲染：
/// 已点亮显示彩色 SVG，未点亮显示灰色剪影（同张 SVG 用 ColorFilter 染灰）。
class CharacterScreen extends ConsumerWidget {
  const CharacterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentChar = ref.watch(currentCharacterProvider);
    final catalog = ref.watch(characterCatalogProvider);
    final catalogData = catalog.asData?.value;
    // 当前角色为后台上传/云端下载素材时的本地 SVG 路径（内置素材为 null）
    final currentFilePath = catalogData?.uploadedFilePaths[currentChar];
    // 全解锁模式：所有角色均可直接选用（便于测试随意切换填充角色；
    // 正式版恢复为 characterCollectionProvider 的里程碑解锁集合）
    final collected = catalogData?.allIds ?? characters.keys.toSet();
    // 会员权益：免费用户仅可使用「每日」分类，其余分类为会员专属
    final isMember = ref.watch(membershipProvider).isMember;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 随机按钮 + X 关闭 + 当前角色卡片
              _HeaderBar(
                currentChar: currentChar,
                currentFilePath: currentFilePath,
                collectedCount: collected.length,
                displayNames: catalogData?.displayNames,
                totalCount: collected.length,
              ),
              Expanded(
                child: catalog.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (e, _) => Center(
                    child: Text('角色目录加载失败：$e'),
                  ),
                  data: (state) => ListView(
                    padding: const EdgeInsets.only(top: 4, bottom: 32),
                    children: [
                      // 分类列表来自后台管理目录层（已过滤下架素材、合并上传素材）
                      for (final cat in state.categories)
                        _CategorySection(
                          category: cat,
                          currentChar: currentChar,
                          collectedIds: collected,
                          uploadedFilePaths: state.uploadedFilePaths,
                          locked: cat.id != 'daily' && !isMember,
                          onLockedTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MembershipScreen(
                                  feature: '全部动物角色'),
                            ),
                          ),
                          onTapCharacter: (id) {
                            if (collected.contains(id)) {
                              ref
                                  .read(currentCharacterProvider.notifier)
                                  .select(id)
                                  .then((_) {
                                // 切换角色即时同步桌面小组件（重渲染角色 PNG）
                                syncWidgetFromSettings(ref.read);
                              });
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('继续喝水，累计饮水量达到里程碑即可点亮新角色'),
                                ),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部固定头部
class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.currentChar,
    required this.collectedCount,
    required this.totalCount,
    this.currentFilePath,
    this.displayNames,
  });

  final String currentChar;

  /// 当前角色为后台上传素材时的本地 SVG 路径（内置素材为 null）
  final String? currentFilePath;

  /// 角色 id → 显示名称（含后台新增/改名的角色）
  final Map<String, String>? displayNames;

  /// 已点亮（收集）角色数
  final int collectedCount;

  /// 当前可见角色总数（含后台新增）
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 随机按钮 + X 关闭
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.refresh, size: 16, color: Color(0xFF1C1C1E)),
                      SizedBox(width: 4),
                      Text(
                        '随机',
                        style: TextStyle(
                          color: Color(0xFF1C1C1E),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE5E5EA),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 18, color: Colors.black),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 2. 当前角色展示（跟随 currentCharacterProvider 动态渲染）
          _CurrentCharacterCard(
            animalId: currentChar,
            filePath: currentFilePath,
            collectedCount: collectedCount,
            totalCount: totalCount,
            displayName: displayNames?[currentChar],
          ),
        ],
      ),
    );
  }
}

/// 当前角色展示卡片：彩色插画 + 名字 + 描述 + 进度（随选中角色实时切换）
class _CurrentCharacterCard extends StatelessWidget {
  const _CurrentCharacterCard({
    required this.animalId,
    required this.collectedCount,
    required this.totalCount,
    this.filePath,
    this.displayName,
  });

  final String animalId;

  /// 当前角色为后台上传素材时的本地 SVG 路径（内置素材为 null）
  final String? filePath;

  /// 已点亮（收集）角色数
  final int collectedCount;

  /// 当前可见角色总数（含后台新增）
  final int totalCount;

  /// 后台下发的显示名称（未下发时用内置名称）
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: CharacterArt(
                  animalId: animalId,
                  unlocked: true,
                  size: 76,
                  filePath: filePath,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            displayName ?? characters[animalId]?.displayName ?? '角色',
            style: const TextStyle(
              color: Color(0xFF1C1C1E),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '完成你的饮水目标。第二天收集新的角色！',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '已收集 $collectedCount 个，共 $totalCount 个',
            style: const TextStyle(
              color: Color(0xFF5AC8FA),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类区段：进度药丸 + 标题 + 副标题 + 5 列网格
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.currentChar,
    required this.collectedIds,
    required this.uploadedFilePaths,
    required this.locked,
    required this.onLockedTap,
    required this.onTapCharacter,
  });

  final CharacterCategory category;
  final String currentChar;
  final Set<String> collectedIds;
  final Map<String, String> uploadedFilePaths;

  /// 会员专属分类且当前非会员：整组显示锁标，点击进付费墙
  final bool locked;
  final VoidCallback onLockedTap;
  final ValueChanged<String> onTapCharacter;

  @override
  Widget build(BuildContext context) {
    final cat = category;
    final collectedCount =
        cat.characterIds.where(collectedIds.contains).length;
    // 排序：已点亮（收集）的角色依次排到未点亮角色前面
    final orderedIds = [
      ...cat.characterIds.where(collectedIds.contains),
      ...cat.characterIds.where((id) => !collectedIds.contains(id)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cat.color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$collectedCount/${cat.characterIds.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    cat.name,
                    style: TextStyle(
                      color: cat.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (locked) ...[
                    const SizedBox(width: 5),
                    Icon(Icons.lock, size: 14, color: cat.color),
                  ],
                ],
              ),
            ],
          ),
          if (cat.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              cat.subtitle!,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
            children: [
              for (final id in orderedIds)
                _CharacterGridCard(
                  animalId: id,
                  color: cat.color,
                  unlocked: collectedIds.contains(id),
                  selected: currentChar == id,
                  filePath: uploadedFilePaths[id],
                  locked: locked,
                  onTap: () => locked ? onLockedTap() : onTapCharacter(id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 角色网格卡片：分类色浅底 + CharacterArt 插画 + 点击切换首页角色
class _CharacterGridCard extends StatelessWidget {
  const _CharacterGridCard({
    required this.animalId,
    required this.color,
    required this.unlocked,
    required this.selected,
    required this.locked,
    required this.onTap,
    this.filePath,
  });

  final String animalId;
  final Color color;
  final bool unlocked;
  final bool selected;

  /// 会员专属且未开通：卡片右下角显示锁标
  final bool locked;
  final VoidCallback onTap;

  /// 后台上传素材的本地 SVG 路径（内置素材为 null）
  final String? filePath;

  @override
  Widget build(BuildContext context) {
    // 当前选中的卡片用分类色描边强调，已解锁但未选中用浅描边
    final border = selected
        ? Border.all(color: color, width: 2.5)
        : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(12),
          border: border,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Center(
                child: CharacterArt(
                  animalId: animalId,
                  unlocked: unlocked,
                  size: 44,
                  filePath: filePath,
                ),
              ),
            ),
            if (locked)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0A63C),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock,
                      size: 11, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
