import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 取 Token — 历史记录存储
/// 字段: [{phone, tokenOnline, ecsToken, appId, at}]
class UnicomHistoryItem {
  final String phone;
  final String tokenOnline;
  final String ecsToken;
  final String appId;
  final int at;

  UnicomHistoryItem({
    required this.phone,
    required this.tokenOnline,
    required this.ecsToken,
    required this.appId,
    required this.at,
  });

  factory UnicomHistoryItem.fromJson(Map<String, dynamic> j) => UnicomHistoryItem(
        phone: j['phone'] ?? '',
        tokenOnline: j['tokenOnline'] ?? '',
        ecsToken: j['ecsToken'] ?? '',
        appId: j['appId'] ?? '',
        at: j['at'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'tokenOnline': tokenOnline,
        'ecsToken': ecsToken,
        'appId': appId,
        'at': at,
      };
}

class UnicomHistoryStore {
  static const _key = 'unicom_history';

  static Future<List<UnicomHistoryItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '[]';
    try {
      final arr = jsonDecode(raw) as List;
      return arr
          .map((e) => UnicomHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 同一号码去重，新的在前，最多 20 条
  static Future<void> save(UnicomHistoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final next = [
      item,
      ...list.where((i) => i.phone != item.phone),
    ].take(20).map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(next));
  }

  static Future<void> delete(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final filtered = list.where((i) => i.phone != phone).toList();
    await prefs.setString(
        _key, jsonEncode(filtered.map((e) => e.toJson()).toList()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, '[]');
  }
}
