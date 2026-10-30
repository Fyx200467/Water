import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/providers.dart';
import '../../../shared/models/drink_entry.dart';

/// CSV 导出结果
enum CsvExportResult { ok, empty, failed }

/// 导出全部饮水记录为 CSV 并调起系统分享面板（会员权益）
///
/// 会员校验由调用方负责；这里只负责取数、拼 CSV、落盘与分享。
Future<CsvExportResult> exportAllEntriesCsv(WidgetRef ref) async {
  final storage = await ref.read(localStorageProvider.future);
  final now = DateTime.now();
  final entries = (await storage.loadEntriesForRange(
    DateTime(2000),
    DateTime(now.year, now.month, now.day + 1),
  ))
      .where((e) => !e.deleted)
      .toList()
    ..sort((a, b) => a.drankAt.compareTo(b.drankAt));
  if (entries.isEmpty) return CsvExportResult.empty;

  final dateFmt = DateFormat('yyyy-MM-dd');
  final timeFmt = DateFormat('HH:mm');
  final csv = StringBuffer('日期,时间,饮品,分类,容量(ml),有效水分(ml),热量(kcal)\n');
  for (final DrinkEntry e in entries) {
    final name = e.beverageName.replaceAll('"', '""');
    csv.write('${dateFmt.format(e.drankAt)},${timeFmt.format(e.drankAt)},'
        '"$name",${e.beverageCategory.label},${e.volumeMl},'
        '${e.effectiveMl},${e.calories < 0 ? '' : e.calories}\n');
  }

  try {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}water_llama_'
      '${dateFmt.format(now)}.csv',
    );
    // BOM 头：Excel 打开中文不乱码
    await file.writeAsString('\uFEFF$csv', flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: '吨吨饮水记录导出',
        text: '吨吨饮水记录（${entries.length} 条）',
      ),
    );
    return CsvExportResult.ok;
  } catch (_) {
    return CsvExportResult.failed;
  }
}
