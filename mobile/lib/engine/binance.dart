import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/errors.dart';

class Candles {
  final List<int> times;
  final List<double> open, high, low, close, volume;
  Candles(this.times, this.open, this.high, this.low, this.close, this.volume);
  int get length => close.length;
}

/// دریافت کندل‌ها مستقیماً از گوشی (API عمومی بایننس، بدون کلید)
class Binance {
  static const _bases = [
    'https://api.binance.com',
    'https://data-api.binance.vision',
  ];

  static Future<List<List<dynamic>>> _page(
      String symbol, String interval, int? endTime) async {
    String? lastErr;
    for (final base in _bases) {
      final q = {
        'symbol': symbol,
        'interval': interval,
        'limit': '1000',
        if (endTime != null) 'endTime': '$endTime',
      };
      final uri = Uri.parse('$base/api/v3/klines').replace(queryParameters: q);
      try {
        final r = await http.get(uri).timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) {
          return (jsonDecode(r.body) as List<dynamic>)
              .map((e) => e as List<dynamic>)
              .toList();
        }
        lastErr = 'HTTP ${r.statusCode}';
        if (r.statusCode == 400) {
          throw ApiException('نماد $symbol نامعتبر است.');
        }
      } on ApiException {
        rethrow;
      } catch (e) {
        lastErr = '$e';
      }
    }
    if (lastErr != null && (lastErr.contains('451') || lastErr.contains('403'))) {
      throw ApiException(
          'بایننس از شبکه یا منطقه فعلی شما در دسترس نیست. VPN را بررسی کنید.');
    }
    throw ApiException('دریافت داده از بایننس ممکن نشد. اینترنت را بررسی کنید.');
  }

  static Future<Candles> klines(String symbol, String interval,
      {int total = 5000}) async {
    var all = <List<dynamic>>[];
    int? endTime;
    while (all.length < total) {
      final page = await _page(symbol, interval, endTime);
      if (page.isEmpty) break;
      all = [...page, ...all];
      endTime = (page.first[0] as int) - 1;
      if (page.length < 1000) break;
    }
    if (all.length > total) all = all.sublist(all.length - total);
    // کندل آخر اگر هنوز بسته نشده، حذف شود
    final now = DateTime.now().millisecondsSinceEpoch;
    if (all.isNotEmpty && (all.last[6] as int) > now) {
      all = all.sublist(0, all.length - 1);
    }
    double d(dynamic v) => double.parse(v as String);
    return Candles(
      all.map((r) => r[0] as int).toList(),
      all.map((r) => d(r[1])).toList(),
      all.map((r) => d(r[2])).toList(),
      all.map((r) => d(r[3])).toList(),
      all.map((r) => d(r[4])).toList(),
      all.map((r) => d(r[5])).toList(),
    );
  }
}
