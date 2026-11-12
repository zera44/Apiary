import 'dart:convert';

import 'package:http/http.dart' as http;

/// Офіційні курси НБУ (гривень за одиницю валюти): код -> курс.
/// Публічний API без ключа: https://bank.gov.ua/NBUStatService
const kNbuRatesUrl = 'https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json';

/// Розбирає відповідь НБУ: `[{"cc":"USD","rate":41.2,...}, ...]`.
/// Некоректні записи пропускає; зовсім не схожа відповідь - [FormatException].
Map<String, double> parseNbuRates(String body) {
  final data = jsonDecode(body);
  if (data is! List) throw const FormatException('відповідь НБУ не список');
  final out = <String, double>{};
  for (final e in data) {
    if (e is! Map) continue;
    final cc = e['cc'];
    final rate = e['rate'];
    if (cc is String && rate is num && rate > 0 && rate.isFinite) out[cc.toUpperCase()] = rate.toDouble();
  }
  return out;
}

/// Завантажує поточні курси; null - немає зв'язку чи відповідь не така.
Future<Map<String, double>?> fetchNbuRates({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse(kNbuRatesUrl)).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final rates = parseNbuRates(utf8.decode(r.bodyBytes));
    return rates.isEmpty ? null : rates;
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}
