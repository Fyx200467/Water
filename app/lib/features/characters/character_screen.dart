import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'character_art.dart';
import 'character_data.dart';
import 'current_character_provider.dart';

/// 角色展示页：从底部滑出的独立全屏页面（不可拖拽关闭，只能点 X 返回）
///
/// 头部固定（随机按钮 + 关闭 + 当前角色卡片 + 收集按钮 + 宣传横幅），
/// 下方 12 个分类网格上下滚动，每个卡片用 CharacterArt 渲染：
/// 已点亮显示彩色 SVG，未点亮显示灰色剪影（同张 SVG 用 ColorFilter 染灰）。
class CharacterScreen extends ConsumerWidget {
  const CharacterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentChar = ref.watch(currentCharacterProvider);
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
              const _HeaderBar(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 32),
                  children: [
                    for (final cat in characterCategories)
                      _CategorySection(
                        category: cat,
                        currentChar: currentChar,
                        onTapCharacter: (id) => ref
                            .read(currentCharacterProvider.notifier)
                            .select(id),
                      ),
                  ],
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
  const _HeaderBar();

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
          // 2. 当前角色展示（羊驼卢娜）
          const _CurrentCharacterCard(),
          const SizedBox(height: 10),
          // 3. 收集角色按钮
          const _CollectButton(),
          const SizedBox(height: 10),
          // 4. 宣传横幅
          const _PromoBanner(),
        ],
      ),
    );
  }
}

/// 当前角色展示卡片：彩色羊驼卢娜插画 + 名字 + 描述 + 进度
class _CurrentCharacterCard extends StatelessWidget {
  const _CurrentCharacterCard();

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
                  animalId: 'alpaca',
                  unlocked: true,
                  size: 76,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '羊驼卢娜',
            style: TextStyle(
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
            '已收集 ${defaultUnlockedIds.length} 个，共 $totalCharacterCount 个',
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

/// 收集角色按钮（禁用态，带"0"徽章）
class _CollectButton extends StatelessWidget {
  const _CollectButton();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.cake, size: 22, color: Color(0xFF1C1C1E)),
            const SizedBox(width: 8),
            const Text(
              '收集角色',
              style: TextStyle(
                color: Color(0xFF1C1C1E),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF8E8E93).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '0',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 蓝青色宣传横幅
class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF5AC8FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        '要分享到社交媒体？🤗 @waterllama_app 提及我们，我们将回复你！',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
      ),
    );
  }
}

/// 分类区段：进度药丸 + 标题 + 副标题 + 5 列网格
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.currentChar,
    required this.onTapCharacter,
  });

  final CharacterCategory category;
  final String currentChar;
  final ValueChanged<String> onTapCharacter;

  @override
  Widget build(BuildContext context) {
    final cat = category;
    final unlockedCount = cat.characterIds
        .where((id) => defaultUnlockedIds.contains(id))
        .length;

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
                  '$unlockedCount/${cat.characterIds.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                cat.name,
                style: TextStyle(
                  color: cat.color,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
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
              for (final id in cat.characterIds)
                _CharacterGridCard(
                  animalId: id,
                  color: cat.color,
                  unlocked: defaultUnlockedIds.contains(id),
                  selected: currentChar == id,
                  onTap: () => onTapCharacter(id),
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
    required this.onTap,
  });

  final String animalId;
  final Color color;
  final bool unlocked;
  final bool selected;
  final VoidCallback onTap;

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
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Center(
            child: CharacterArt(
              animalId: animalId,
              unlocked: unlocked,
              size: 44,
            ),
          ),
        ),
      ),
    );
  }
}
