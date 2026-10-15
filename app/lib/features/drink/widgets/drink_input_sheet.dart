import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/beverage.dart';
import '../../../shared/models/drink_entry.dart';
import '../../home/providers/home_providers.dart';
import '../services/hydration_calculator.dart';

/// PRD §2.3 饮水彔入 BottomSheet
/// 预设容量 100/200/300/500/1000 + 自定义
/// 饮品库选择 + 水分折算预览
class DrinkInputSheet extends ConsumerStatefulWidget {
  const DrinkInputSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const DrinkInputSheet(),
    );
  }

  @override
  ConsumerState<DrinkInputSheet> createState() => _DrinkInputSheetState();
}

class _DrinkInputSheetState extends ConsumerState<DrinkInputSheet> {
  Beverage _beverage = Beverage.presets[0];
  int _volume = 250;
  bool _custom = false;
  final _customCtrl = TextEditingController(text: '250');

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  int get _effective =>
      HydrationCalculator.previewEffectiveMl(_beverage, _volume);

  Future<void> _submit() async {
    final entry = DrinkEntry.create(
      beverage: _beverage,
      volumeMl: _volume,
    );
    await ref.read(todayEntriesProvider.notifier).add(entry);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beverages = Beverage.presets.toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16, 12, 16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('记录喝水', style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 20),

            // 饮品分类横向
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: beverages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final b = beverages[i];
                  final selected = b.id == _beverage.id;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _beverage = b;
                      if (! _custom) _volume = b.defaultMl;
                    }),
                    child: Container(
                      width: 60,
                      decoration: BoxDecoration(
                        color: selected
                            ? b.color.withValues(alpha: 0.2)
                            : theme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? b.color : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(b.category.icon, color: b.color),
                          const SizedBox(height: 4),
                          Text(b.name,
                              style: theme.textTheme.labelSmall,
                              textAlign: TextAlign.center,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // 预设容量
            if (!_custom)
              Wrap(
                spacing: 8, runSpacing: 8,
                children: Beverage.presetVolumes.map((v) {
                  final selected = v == _volume;
                  return ChoiceChip(
                    label: Text('$v ml'),
                    selected: selected,
                    onSelected: (_) => setState(() => _volume = v),
                  );
                }).toList(),
              )
            else
              TextField(
                controller: _customCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '自定义容量 (ml)',
                  border: OutlineInputBorder(),
                  suffixText: 'ml',
                ),
                onChanged: (s) {
                  final n = int.tryParse(s);
                  if (n != null && n > 0) {
                    setState(() => _volume = n.clamp(1, 5000));
                  }
                },
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _custom = !_custom;
                    if (_custom) {
                      _customCtrl.text = '$_volume';
                    }
                  });
                },
                child: Text(_custom ? '使用预设' : '自定义容量'),
              ),
            ),

            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('本次摄入', style: theme.textTheme.bodyMedium),
                        Text('$_volume ml · ${_beverage.name}',
                            style: theme.textTheme.titleLarge),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('有效水分', style: theme.textTheme.bodyMedium),
                        Text('$_effective ml',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            )),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.add_circle),
              label: const Text('记录饮水'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
