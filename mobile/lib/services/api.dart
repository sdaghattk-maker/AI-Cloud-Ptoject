import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/signal.dart';
import 'settings.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  Api([String? baseUrl]) : baseUrl = baseUrl ?? Settings.baseUrl;
  final String baseUrl;

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse(baseUrl).replace(path: path, queryParameters: query);
    try {
      // اولین اسکن ممکن است طولانی باشد (دانلود و بک‌تست)
      final r = await http.get(uri).timeout(const Duration(seconds: 240));
      if (r.statusCode != 200) {
        throw ApiException('خطای سرور (${r.statusCode})');
      }
      return jsonDecode(utf8.decode(r.bodyBytes));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
          'اتصال به سرور ممکن نشد. آدرس سرور را در تنظیمات بررسی کنید.');
    }
  }

  Future<List<Signal>> scan() async {
    final data = await _get('/scan') as List<dynamic>;
    return data
        .map((e) => Signal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AnalyzeResult> analyze(String symbol, String tf) async {
    final data =
        await _get('/analyze', {'symbol': symbol.toUpperCase(), 'tf': tf});
    return AnalyzeResult.fromJson(data as Map<String, dynamic>);
  }
}
