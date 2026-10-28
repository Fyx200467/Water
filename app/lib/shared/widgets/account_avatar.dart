import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 账号头像：菜单页账号卡与「账号信息」页共用，保证两处展示一致。
///
/// 展示优先级：
/// 1. 未登录 → 灰色「未登录」用户图标；
/// 2. 已登录且本机有自定义头像（相册 / 拍照）→ 显示本地图片；
/// 3. 已登录但没有自定义头像 → 默认羊驼插画。
///
/// 后续接入 QQ / 微信登录时，只需把第三方头像下载落盘并写入
/// [LocalStorage.accountAvatarPath]，这里无需再改。
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.size,
    required this.loggedIn,
    this.avatarPath,
    this.padding = 2,
    this.background = const Color(0xFFDCEFFD),
  });

  final double size;
  final bool loggedIn;
  final String? avatarPath;
  final double padding;
  final Color background;

  @override
  Widget build(BuildContext context) {
    // 未登录图标本身就带圆形外框，直接按原样式展示，
    // 不再套底色圆形 + 内边距，避免出现「双圈」和底色遮挡
    if (!loggedIn) {
      return SvgPicture.asset(
        'assets/icons/menu/未登录.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }

    final path = avatarPath;
    final hasPhoto = path != null && File(path).existsSync();
    if (hasPhoto) {
      // 上传照片：铺满圆形头像（居中裁剪），外圈白环由外层容器负责
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: ClipOval(
          child: Image.file(File(path), fit: BoxFit.cover),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: background),
      child: ClipOval(
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: SvgPicture.asset(
            'assets/images/characters/alpaca.svg',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
