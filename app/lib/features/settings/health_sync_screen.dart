import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/health/health_sync_service.dart';
import '../../core/storage/providers.dart';
import '../home/providers/home_providers.dart';

/// 设置页「"健康"同步」一行显示「已连接」还是「连接」
final healthSyncEnabledProvider = FutureProvider<bool>((ref) async {
  final storage = await ref.watch(localStorageProvider.future);
  return storage.healthSyncEnabled;
});

/// 健康同步设置页
///
/// 主页开关 + 「同步到健康 App」按钮：
///  * 首次开启会申请读写授权并补录最近 30 天饮水
///  * iOS 无 HealthKit / Android 未装 Health Connect 时给出引导
///  * 点击「立即同步」可在不重开授权的情况下手动补跑
class HealthSyncScreen extends ConsumerStatefulWidget {
  const HealthSyncScreen({super.key});

  @override
  ConsumerState<HealthSyncScreen> createState() => _HealthSyncScreenState();
}

class _HealthSyncScreenState extends ConsumerState<HealthSyncScreen> {
  static const _cyan = Color(0xFF35B5D6);
  static const _textDark = Color(0xFF1C1C1E);

  bool _working = false;
  bool _needInstall = false;
  String _status = '未开启';

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final storage = await ref.read(localStorageProvider.future);
    final enabled = storage.healthSyncEnabled;
    final lastAt = storage.healthLastSyncAt;
    final avail = await HealthSyncService.availability();
    String status;
    if (enabled) {
      status = switch (avail) {
        HealthAvailability.ready =>
          lastAt == null ? '已连接' : '上次同步 ${_fmtDate(lastAt)}',
        HealthAvailability.needInstall => '需要安装 Health Connect',
        HealthAvailability.notSupported => '此设备不支持',
      };
    } else {
      status = avail == HealthAvailability.notSupported ? '此设备不支持' : '未开启';
    }
    if (mounted) {
      setState(() {
        _status = status;
        _needInstall = avail == HealthAvailability.needInstall;
      });
    }
  }

  Future<void> _toggle(bool on) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final storage = await ref.read(localStorageProvider.future);
      if (on) {
        // 先申请授权（iOS 会弹系统授权、Android 走 Health Connect）
        final ok = await HealthSyncService.requestPermissions();
        if (!ok) {
          // 授权被拒或环境不满足：不打开开关，提示去系统里允许
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('未获得健康数据权限，请在系统设置中允许后重试'),
            ));
          }
          return;
        }
        setState(() => _status = '已连接');
        await storage.setHealthSyncEnabled(true);
        // 补录最近 30 天 + 拉取外部饮水
        final report =
            await HealthSyncService.syncNow(storage);
        if (report.imported > 0 && mounted) {
          ref.invalidate(todayEntriesProvider);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已从健康 App 导入 ${report.imported} 条饮水'),
          ));
        }
      } else {
        // 关闭：不再写入/撤回，保留已同步数据（退出健康 App 不再回写）
        await storage.setHealthSyncEnabled(false);
        setState(() => _status = '未开启');
      }
    } finally {
      if (mounted) setState(() => _working = false);
      await _refreshStatus();
    }
  }

  Future<void> _syncNow() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final storage = await ref.read(localStorageProvider.future);
      final report = await HealthSyncService.syncNow(storage);
      if (!mounted) return;
      if (report.failed) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('同步失败，请检查健康数据权限'),
        ));
      } else if (report.imported > 0) {
        ref.invalidate(todayEntriesProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已导入 ${report.imported} 条饮用记录'),
        ));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已是最新')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
      await _refreshStatus();
    }
  }

  Future<void> _installHealthConnect() async {
    await HealthSyncService.installHealthConnect();
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(localStorageProvider).valueOrNull;
    final enabled = storage?.healthSyncEnabled ?? false;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text(
          '"健康"同步',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('同步饮用记录',
                          style: TextStyle(
                              color: _textDark,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        _status,
                        style: const TextStyle(
                            color: Color(0xFF8A8A8E), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: _working ? null : _toggle,
                  activeTrackColor: _cyan,
                  activeThumbColor: Colors.white,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: const Color(0xFFE5E5EA),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_needInstall) ...[
            _button('安装 Health Connect', _installHealthConnect),
            const SizedBox(height: 8),
          ],
          if (enabled) ...[
            _button('立即同步', _syncNow),
            const SizedBox(height: 16),
            const Text(
              '开启后可把 App 里的饮水记录同步到 Apple 健康／Health Connect，'
              '也会读取其他来源的饮水并去重导入。首次开启会补录最近 30 天。',
              style: TextStyle(color: Color(0xFF8A8A8E), fontSize: 12, height: 1.5),
            ),
          ] else
            const Text(
              '开启同步后，App 里的饮水记录会写入 Apple 健康／健康运动。'
              '你随时都可以在这里关闭，已同步的数据不会从健康 App 里删除。',
              style: TextStyle(color: Color(0xFF8A8A8E), fontSize: 12, height: 1.5),
            ),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap) {
    return InkWell(
      onTap: _working ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: _working
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _cyan),
              )
            : Text(label,
                style: const TextStyle(
                    color: Color(0xFF007AFF), fontSize: 16)),
      ),
    );
  }

  static String _fmtDate(DateTime t) {
    final now = DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final y = today.difference(d).inDays;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';
    if (y == 0) return '今天 $time';
    if (y == 1) return '昨天 $time';
    return '${t.month}月${t.day}日 $time';
  }
}