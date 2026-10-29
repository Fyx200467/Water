import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/storage/providers.dart';
import '../../core/sync/sync_api.dart';

const _bg = Color(0xFFF5F6F8);
const _ink = Color(0xFF1C1C1E);
const _gray = Color(0xFF8E8E93);
const _line = Color(0xFFECECEF);
const _accent = Color(0xFF3BB3DB);

/// 帮助与支持：常见问题 + 问题反馈（内测阶段收集问题的主要入口）
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _contentCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  bool _submitting = false;

  static const _faqs = [
    (
      '打卡记录会丢吗？',
      '开启「账号与云备份」登录后，记录会同步到云端；'
          '换设备登录同一账号即可恢复。',
    ),
    (
      '会员是怎么开通的？',
      '内测阶段无需付款：提交开通申请后由运营确认，确认后自动生效。',
    ),
    (
      '为什么每日角色变少了？',
      '免费用户每天从随机池中解锁部分角色，会员可解锁全部角色。',
    ),
    (
      '桌面小组件不刷新怎么办？',
      '在设置页进入「小组件」，打开再关闭一次即可触发刷新。',
    ),
  ];

  @override
  void dispose() {
    _contentCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentCtrl.text.trim();
    if (content.length < 5) {
      _toast('请至少填写 5 个字的问题描述');
      return;
    }
    setState(() => _submitting = true);
    try {
      final storage = await ref.read(localStorageProvider.future);
      final token = storage.syncToken;
      if (token == null || token.isEmpty) {
        _toast('请先登录账号后再提交反馈');
        return;
      }
      await SyncApi.submitFeedback(
        token,
        content: content,
        contact: _contactCtrl.text.trim(),
        appVersion: kAppVersion,
        platform: Platform.operatingSystem,
        device: '${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion}',
      );
      if (!mounted) return;
      _contentCtrl.clear();
      _contactCtrl.clear();
      _toast('已提交，感谢你的反馈');
    } catch (_) {
      if (!mounted) return;
      _toast('提交失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _bg,
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 32),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                color: _ink,
              ),
              const Text(
                '帮助与支持',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '常见问题',
            style: TextStyle(
              fontSize: 13,
              color: _gray,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          ..._faqs.map(
            (f) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(
                  f.$1,
                  style: const TextStyle(fontSize: 14, color: _ink),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      f.$2,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _gray,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '问题反馈',
            style: TextStyle(
              fontSize: 13,
              color: _gray,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _contentCtrl,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText: '描述你遇到的问题，例如：什么操作、看到什么、期望是什么',
                    hintStyle: TextStyle(fontSize: 13, color: _gray),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: _line),
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _line),
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    counterStyle: TextStyle(fontSize: 11, color: _gray),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _contactCtrl,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    hintText: '联系方式（选填，方便回访）',
                    hintStyle: TextStyle(fontSize: 13, color: _gray),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: _line),
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _line),
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '提交时会附带你当前的 App 版本与系统信息，便于定位问题。',
                  style: TextStyle(fontSize: 11, color: _gray),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _submitting ? '提交中…' : '提交反馈',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '吨吨 v$kAppVersion（内测版）',
              style: const TextStyle(fontSize: 11, color: _gray),
            ),
          ),
        ],
      ),
    );
  }
}
