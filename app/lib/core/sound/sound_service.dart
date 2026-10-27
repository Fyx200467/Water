import 'package:flutter/services.dart';

import '../../features/settings/settings_flags.dart';

/// App 内音效
///
/// 通过原生 MethodChannel 播放 `res/raw/water_add.m4a`（参考竞品的加水音效）：
/// - `goal`：完成当日目标
/// - `hit` ：弹弓水滴命中角色
///
/// 开关由「App、声音、动画」页的 **App 声音** 控制；
/// 小部件点按音效走原生 QuickAddReceiver，不经过这里。
class SoundService {
  SoundService._();

  static const _channel = MethodChannel('waterllama/sound');

  /// 最近一次播放时刻：同一瞬间的「命中 + 完成目标」只播一次，
  /// 也避免连续弹射时音效叠加（约 900ms 内的重复请求直接忽略）
  static DateTime? _lastPlayedAt;

  static Future<void> _play(String kind) async {
    final now = DateTime.now();
    final last = _lastPlayedAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastPlayedAt = now;
    try {
      await _channel.invokeMethod<bool>('play', {'kind': kind});
    } catch (_) {
      // 非 Android / 通道不可用：静默降级
    }
  }

  /// 完成当日目标：轻震动 + 加水音效
  static Future<void> goalReached() async {
    if (!SettingsFlags.instance.appSounds) return;
    HapticFeedback.mediumImpact();
    await _play('goal');
  }

  /// 弹弓水滴命中角色：短促提示音（震动由调用方负责）
  static Future<void> dropHit() async {
    if (!SettingsFlags.instance.appSounds) return;
    await _play('hit');
  }

  /// 试听提醒音效（用户主动点选时调用，不受 App 声音开关限制）
  static Future<void> previewReminder(String soundKey) async {
    try {
      await _channel.invokeMethod<bool>('preview', {'sound': soundKey});
    } catch (_) {
      // 非 Android / 通道不可用：静默降级
    }
  }
}
