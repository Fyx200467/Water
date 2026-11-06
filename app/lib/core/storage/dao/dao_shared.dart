import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'dao_keys.dart';

/// 当前记录归属：登录账号 ID；空串表示游客（未登录）
String ownerOf(SharedPreferences prefs) =>
    prefs.getString(StorageKeys.syncUserId) ?? '';

String ownerSuffix(String owner) => owner.isEmpty ? 'guest' : owner;

String nowIso() => DateTime.now().toUtc().toIso8601String();

/// [a] 是否比 [b] 更新时间更晚（ISO 时间串，解析失败时退化为字符串比较）
bool isNewer(String a, String b) {
  final ta = DateTime.tryParse(a);
  final tb = DateTime.tryParse(b);
  if (ta != null && tb != null) return ta.isAfter(tb);
  return a.compareTo(b) > 0;
}

/// 偏好桶解码：容错老数据（直接存的裸值）
Map<String, Map<String, dynamic>> decodeSettings(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final out = <String, Map<String, dynamic>>{};
    decoded.forEach((k, v) {
      out[k.toString()] = v is Map
          ? Map<String, dynamic>.from(v)
          : {'v': v, 'at': ''};
    });
    return out;
  } catch (_) {
    return {};
  }
}

Map<String, String> decodeStringMap(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
  } catch (_) {
    return {};
  }
}

Map<String, dynamic>? decodeJsonMap(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

List<Map<String, dynamic>> decodePendingList(String? raw) {
  // 必须返回可增删的列表：调用方会直接 add（const [] 会抛
  // Unsupported operation: Cannot add to an unmodifiable list）
  if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
}

/// 老版本偏好是 jsonEncode 字符串：能解析就还原成原始类型
dynamic decodeSettingValue(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return raw;
  }
}

String dayKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// 简易 map 编码（不依赖 dart:convert 暴露的复杂结构）
String encodeMap(Map<String, dynamic> m) {
  return m.entries
      .map((e) {
        final v = e.value;
        final s = v == null ? '' : v.toString();
        // 转义分号与等号
        final ev = s.replaceAll(';', '\\;').replaceAll('=', '\\=');
        return '${e.key}=$ev';
      })
      .join(';');
}

Map<String, dynamic> decodeMap(String s) {
  if (s.isEmpty) return {};
  final out = <String, dynamic>{};
  // 先按未转义的分号拆分
  final parts = splitUnescaped(s, ';');
  for (final part in parts) {
    final kv = splitUnescaped(part, '=');
    if (kv.length == 2) {
      final k = kv[0];
      var v = kv[1].replaceAll('\\;', ';').replaceAll('\\=', '=');
      if (v == 'null' || v.isEmpty) v = '';
      out[k] = v;
    }
  }
  return out;
}

List<String> splitUnescaped(String s, String sep) {
  final out = <String>[];
  var buf = StringBuffer();
  var i = 0;
  while (i < s.length) {
    if (s[i] == '\\') {
      buf.write(s[i]);
      i++;
      if (i < s.length) buf.write(s[i]);
    } else if (s.substring(i).startsWith(sep)) {
      out.add(buf.toString());
      buf = StringBuffer();
      i += sep.length;
      continue;
    } else {
      buf.write(s[i]);
    }
    i++;
  }
  out.add(buf.toString());
  return out;
}
