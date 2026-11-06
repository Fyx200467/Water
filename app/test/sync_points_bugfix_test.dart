import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:water_llama/core/storage/local_storage.dart';
import 'package:water_llama/core/time/logical_day.dart';
import 'package:water_llama/shared/models/beverage.dart';
import 'package:water_llama/shared/models/drink_entry.dart';

DrinkEntry _entry({
  required String clientId,
  required int volume,
  required DateTime updatedAt,
  bool synced = false,
}) {
  return DrinkEntry(
    clientId: clientId,
    beverageId: 'water_pure',
    beverageCategory: BeverageCategory.water,
    beverageName: '纯净水',
    volumeMl: volume,
    effectiveMl: volume,
    drankAt: updatedAt,
    synced: synced,
    updatedAt: updatedAt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('跨天后同步摘要会清空领取标记（签到/达标可重新领取）', () async {
    SharedPreferences.setMockInitialValues({
      'points_state': '{"balance":10,"dayKey":"2000-01-01",'
          '"claimed":["checkin","milestone"],"history":[]}',
    });
    final storage = await LocalStorage.init();
    final todayKey = LogicalDay.keyString(LogicalDay.today());
    await storage.applyPointsSummary(8, const []);
    final snapshot = storage.loadPointsSnapshot()!;
    expect(snapshot['dayKey'], todayKey);
    expect(snapshot['claimed'], isEmpty);
  });

  test('同一天同步摘要保留已领取标记', () async {
    final todayKey = LogicalDay.keyString(LogicalDay.today());
    SharedPreferences.setMockInitialValues({
      'points_state': '{"balance":10,"dayKey":"$todayKey",'
          '"claimed":["checkin"],"history":[]}',
    });
    final storage = await LocalStorage.init();
    await storage.applyPointsSummary(8, const []);
    final snapshot = storage.loadPointsSnapshot()!;
    expect(snapshot['dayKey'], todayKey);
    expect(snapshot['claimed'], ['checkin']);
  });

  test('拉取远端旧记录不覆盖本机更新的未同步记录', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await LocalStorage.init();
    final now = DateTime.now();
    final newer = _entry(
      clientId: 'c1',
      volume: 350,
      updatedAt: now,
    );
    await storage.insertDrinkEntry(newer);

    await storage.applyRemoteEntry(
      _entry(
        clientId: 'c1',
        volume: 200,
        updatedAt: now.subtract(const Duration(hours: 2)),
        synced: true,
      ),
    );

    final entries = await storage.loadEntriesForDay(LogicalDay.today());
    final local = entries.firstWhere((e) => e.clientId == 'c1');
    expect(local.volumeMl, 350, reason: '本机未同步的新版本不能被旧的远端记录覆盖');
    expect(local.synced, isFalse);
  });

  test('拉取远端更新记录会覆盖本机旧记录', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await LocalStorage.init();
    final now = DateTime.now();
    await storage.insertDrinkEntry(
      _entry(clientId: 'c2', volume: 200, updatedAt: now),
    );
    await storage.applyRemoteEntry(
      _entry(
        clientId: 'c2',
        volume: 500,
        updatedAt: now.add(const Duration(minutes: 5)),
        synced: true,
      ),
    );
    final entries = await storage.loadEntriesForDay(LogicalDay.today());
    final local = entries.firstWhere((e) => e.clientId == 'c2');
    expect(local.volumeMl, 500);
    expect(local.synced, isTrue);
  });
}
