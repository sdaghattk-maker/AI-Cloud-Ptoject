import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/signal.dart';
import 'errors.dart';
import 'settings.dart';

const _systemPrompt =
    'تو یک تحلیلگر ریسک‌محور بازار کریپتو هستی. فقط از داده‌هایی که کاربر می‌دهد استفاده کن؛ '
    'هیچ عدد، قیمت یا خبر جدیدی نساز و هیچ سود تضمین‌شده‌ای وعده نده. '
    'پاسخ را به فارسی ساده و حداکثر در ۱۵۰ کلمه بنویس، با این چهار بخش کوتاه: '
    '«وضعیت کلی»، «دلیل سیگنال»، «ریسک‌ها و شرط ابطال»، «مدیریت معامله». '
    'اگر آمار بک‌تست یا فیلتر ML ضعیف است، صریح بگو. در پایان یک جمله هشدار کوتاه بنویس.';

/// متن ورودی AI از روی سیگنال محاسبه‌شده (AI فقط توضیح می‌دهد، محاسبه نمی‌کند)
String buildPrompt(Signal s) {
  final b = s.backtest;
  final ctx = s.context.entries.map((e) => '${e.key}=${e.value}').join(', ');
  return 'نماد: ${s.symbol} | تایم‌فریم: ${s.timeframe} | جهت: ${s.side}\n'
      'قیمت ورود: ${fmt(s.entry)} | حد ضرر: ${fmt(s.sl)} | هدف اول: ${fmt(s.tp1)} | '
      'هدف دوم: ${fmt(s.tp2)}\n'
      'نسبت ریسک به ریوارد تا هدف دوم: 1:${s.rr2.toStringAsFixed(1)} | '
      'فاصله حد ضرر: ${s.riskPct.toStringAsFixed(2)}٪ | امتیاز: ${s.score.toStringAsFixed(0)}/100\n'
      'بک‌تست خارج از نمونه: ${b.trades} معامله، وین‌ریت ${b.winRate}٪، میانگین ${b.expectancyR}R، '
      'ProfitFactor ${b.profitFactor}، بیشینه افت ${b.maxDdR}R\n'
      'فیلتر ML: ${s.mlStatus.isEmpty ? 'نامشخص' : s.mlStatus}\n'
      'اندیکاتورها در لحظه سیگنال: ${ctx.isEmpty ? 'نامشخص' : ctx}';
}

class Llm {
  static final Map<String, String> _cache = {};

  static Uri _uri(String path) {
    var b = Settings.llmBaseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return Uri.parse('$b$path');
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${Settings.llmKey}',
      };

  static ApiException _httpError(int code) {
    if (code == 401 || code == 403) {
      return ApiException('کلید API نامعتبر است یا اجازه دسترسی ندارد.');
    }
    if (code == 404) {
      return ApiException('مدل یا آدرس پیدا نشد. نام مدل را از «دریافت لیست مدل‌ها» انتخاب کنید.');
    }
    if (code == 429) {
      return ApiException('سقف درخواست رایگان پر شده؛ کمی بعد دوباره امتحان کنید.');
    }
    return ApiException('خطای سرویس AI ($code).');
  }

  static Future<String> analyze(Signal s) async {
    if (!Settings.llmReady) {
      throw ApiException('ابتدا در تنظیمات، آدرس، مدل و کلید AI را وارد کنید.');
    }
    final key = '${s.symbol}_${s.timeframe}_${s.time}_${Settings.llmModel}';
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final r = await http
          .post(
            _uri('/chat/completions'),
            headers: _headers,
            body: jsonEncode({
              'model': Settings.llmModel,
              'temperature': 0.3,
              'messages': [
                {'role': 'system', 'content': _systemPrompt},
                {'role': 'user', 'content': buildPrompt(s)},
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) throw _httpError(r.statusCode);
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final text =
          ((data['choices'] as List<dynamic>).first as Map<String, dynamic>)['message']
              ['content'] as String;
      final out = text.trim();
      if (out.isEmpty) throw ApiException('پاسخ خالی از سرویس AI دریافت شد.');
      _cache[key] = out;
      return out;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
          'اتصال به سرویس AI ممکن نشد. اینترنت، آدرس و دسترسی منطقه‌ای سرویس را بررسی کنید.');
    }
  }

  /// فهرست مدل‌های در دسترس (برای انتخاب نام درست مدل)
  static Future<List<String>> listModels() async {
    if (Settings.llmBaseUrl.isEmpty || Settings.llmKey.isEmpty) {
      throw ApiException('اول آدرس و کلید را وارد کنید.');
    }
    try {
      final r = await http
          .get(_uri('/models'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) throw _httpError(r.statusCode);
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final list = (data['data'] ?? data['models'] ?? <dynamic>[]) as List<dynamic>;
      final ids = list
          .map((e) => ((e as Map<String, dynamic>)['id'] ?? e['name'] ?? '').toString())
          .map((id) => id.startsWith('models/') ? id.substring(7) : id)
          .where((id) => id.isNotEmpty)
          .toList()
        ..sort();
      if (ids.isEmpty) throw ApiException('فهرست مدل خالی بود.');
      return ids;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('دریافت فهرست مدل‌ها ممکن نشد. آدرس و کلید را بررسی کنید.');
    }
  }
}
