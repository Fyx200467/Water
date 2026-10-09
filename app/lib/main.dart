import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

/// PRD §1.3 前端层入口
/// M1：脚手架；M2：首页养成核心 + 饮水彔入
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: WaterLlamaApp()));
}
