import 'package:flutter/material.dart';

import 'tips_deck.dart';

/// 「今日小贴士」查看全部页（对标原版：点击首页「查看全部」跳转，底部滑入）
///
/// 结构：白底纵向滚动，5 个分组纵向排列（进水量 0/9 · 生活小窍门 0/12 ·
/// 美味饮品 0/6 · 健康益处 0/17 · 通用 0/8）。每组 = 标题行（圆角胶囊
/// 「0/N」计数 + 分类色大标题）+ 横向滚动卡片行。
///
/// 卡片 = TipCardFace（与首页堆叠卡同构）：尺寸为堆叠卡的等比缩小
/// （宽高比同 0.78、圆角 32），底层插画区铺满整卡 + 顶层左下文案——
/// 文案在图片顶层，后台上传插画与文案时不产生排版异常（文案先写死）。
class TipsAllScreen extends StatelessWidget {
  const TipsAllScreen({super.key});

  static const _topPad = Color(0xFFE9E9EE);

  /// 页内卡片宽（= 2.2 张可见，对标原版）；高按堆叠卡比例 0.78 等比
  static const _cardW = 172.0;
  static const _cardH = _cardW / 0.78;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 分组纵列表
          Positioned.fill(
            child: ListView.builder(
              padding: EdgeInsets.only(top: topPad + 74, bottom: 40),
              itemCount: TipGroup.all.length,
              itemBuilder: (context, i) => _groupSection(TipGroup.all[i]),
            ),
          ),
          // 顶部圆钮（< 返回 / •••）
          Positioned(
            top: topPad + 8,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _roundBtn(Icons.arrow_back_ios_new, () {
                    Navigator.of(context).maybePop();
                  }),
                  _roundBtn(Icons.more_horiz, () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('功能开发中')),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: _topPad, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, color: const Color(0xFF6B6B70), size: 20),
      ),
    );
  }

  /// 分组区块：标题行 + 横向卡片行
  Widget _groupSection(TipGroup group) {
    final cards = kTipPool.where((c) => c.group == group).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                // 计数胶囊（动态：分子=该组已完成条数，分母=该组实际卡片数；
                // 完成一条实时 +1，与首页牌堆共享同一份 tipsRead 状态）
                ValueListenableBuilder<Set<String>>(
                  valueListenable: tipsRead,
                  builder: (context, read, _) {
                    final done =
                        cards.where((c) => read.contains(c.title)).length;
                    return Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: group.color,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '$done',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '/${cards.length}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Text(
                  group.name,
                  style: TextStyle(
                    color: group.color,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          // 横向卡片行（卡片尺寸 = 堆叠卡等比缩小，标题字号同步等比）
          // 点击卡片 = 标记该条完成（右上角绿勾，胶囊计数实时 +1）
          SizedBox(
            height: _cardH,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) => ValueListenableBuilder<Set<String>>(
                valueListenable: tipsRead,
                builder: (context, read, _) => GestureDetector(
                  onTap: () => markTipRead(cards[i]),
                  child: TipCardFace(
                    data: cards[i],
                    width: _cardW,
                    height: _cardH,
                    titleSize: 15,
                    done: read.contains(cards[i].title),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
