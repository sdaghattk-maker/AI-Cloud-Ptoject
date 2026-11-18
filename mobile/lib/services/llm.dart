import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/signal.dart';
import 'errors.dart';
import 'settings.dart';

const signalSystemPrompt =
    'تو یک تحلیلگر ریسک‌محور بازار کریپتو هستی. فقط از داده‌هایی که کاربر می‌دهد استفاده کن؛ '
    'هیچ عدد، قیمت یا خبر جدیدی نساز و هیچ سود تضمین‌شده‌ای وعده نده. '
    'پاسخ را به فارسی ساده و حداکثر در ۱۵۰ کلمه بنویس، با این چهار بخش کوتاه: '
    '«وضعیت کلی»، «دلیل سیگنال»، «ریسک‌ها و شرط ابطال»، «مدیریت معامله». '
    'اگر آمار بک‌تست یا فیلتر ML ضعیف است، صریح بگو. در پایان یک جمله هشدار کوتاه بنویس.';

const stateSystemPrompt =
    'تو یک تحلیلگر ریسک‌محور بازار کریپتو هستی. فقط از داده‌هایی که کاربر می‌دهد استفاده کن؛ '
    'هیچ عدد، قیمت یا خبر جدیدی نساز، پیش‌بینی قیمت نکن و سیگنال خرید/فروش از خودت نساز. '
    'پاسخ را به فارسی ساده و حداکثر در ۱۵۰ کلمه بنویس، با این بخش‌های کوتاه: '
    '«وضعیت بازار»، «چرا سیگنالی نیست»، «چه چیزی باید اتفاق بیفتد تا شرایط ورود فعال شود»، «ریسک». '
    'اگر بک‌تست لبه آماری نشان نداده، صریح بگو که استراتژی روی این نماد قابل‌اعتماد نیست. '
    'در پایان یک جمله هشدار کوتاه بنویس.';

/// متن ورودی AI از روی سیگنال محاسبه‌شده (AI فقط توضیح می‌دهد، محاسبه نمی‌کند)
String buildPrompt(Signal s) {
  final b = s.backtest;
  final ctx = s.context.entries.map((e) => '${e.key}=${e.value}').join(', ');
  return 'نماد: ${s.symbol} | تایم‌فریم: ${s.timeframe} | جهت: ${s.side} | '
      'استراتژی: ${s.strategy.isEmpty ? 'نامشخص' : s.strategy}\n'
      'قیمت ورود: ${fmt(s.entry)} | حد ضرر: ${fmt(s.sl)} | هدف اول: ${fmt(s.tp1)} | '
      'هدف دوم: ${fmt(s.tp2)}\n'
      'نسبت ریسک به ریوارد تا هدف دوم: 1:${s.rr2.toStringAsFixed(1)} | '
      'فاصله حد ضرر: ${s.riskPct.toStringAsFixed(2)}٪ | امتیاز: ${s.score.toStringAsFixed(0)}/100\n'
      'بک‌تست خارج از نمونه: ${b.trades} معامله، وین‌ریت ${b.winRate}٪، میانگین ${b.expectancyR}R، '
      'ProfitFactor ${b.profitFactor}، بیشینه افت ${b.maxDdR}R، معناداری t=${b.tStat}\n'
      'فیلتر ML: ${s.mlStatus.isEmpty ? 'نامشخص' : s.mlStatus}\n'
      'اندیکاتورها در لحظه سیگنال: ${ctx.isEmpty ? 'نامشخص' : ctx}';
}

/// متن ورودی AI وقتی سیگنالی وجود ندارد (توضیح وضعیت بازار و دلیل نبودن سیگنال)
String buildStatePrompt(AnalyzeResult r) {
  final b = r.backtest;
  final ctx = r.context.entries.map((e) => '${e.key}=${e.value}').join(', ');
  final reason = r.note.isNotEmpty
      ? r.note
      : r.edgeOk
          ? 'لبه آماری بک‌تست تأیید شده ولی شرایط ورود در کندل فعلی کامل نیست.'
          : 'لبه آماری قابل‌اعتماد در بک‌تست تأیید نشده است.';
  return 'نماد: ${r.symbol} | تایم‌فریم: ${r.timeframe} | سیگنال فعال: ندارد\n'
      'دلیل: $reason\n'
      'بک‌تست خارج از نمونه: ${b.trades} معامله، وین‌ریت ${b.winRate}٪، میانگین ${b.expectancyR}R، '
      'ProfitFactor ${b.profitFactor}، بیشینه افت ${b.maxDdR}R، معناداری t=${b.tStat}\n'
      'اندیکاتورها در آخرین کندل بسته‌شده: ${ctx.isEmpty ? 'نامشخص' : ctx}\n'
      'استراتژی‌های بررسی‌شده (فقط برای توضیح؛ قاعده جدید نساز): ۱) روند + پولبک: همسو با روند، RSI بعد از '
      'افت دوباره از ۵۰ بالا بیاید. ۲) شکست کانال: قیمت از بالاترین/پایین‌ترین قیمت چند کندل اخیر '
      'در جهت روند عبور کند. ۳) بازگشت به میانگین در بازار رنج: قیمت بعد از خروج از باند بولینگر به '
      'داخل برگردد. در هر کدام سیگنال فقط وقتی داده می‌شود که بک‌تست خارج از نمونه معنادار باشد '
      'و هزینه کارمزد از ۲۵٪ ریسک بیشتر نشود.';
}

class AiAnswer {
  final String label, model, text;
  final bool ok;
  const AiAnswer(this.label, this.model, this.text, this.ok);
}

class Llm {
  static final Map<String, String> _cache = {};

  static Uri _uri(AiProfile p, String path) {
    var b = p.baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return Uri.parse('$b$path');
  }

  static Map<String, String> _headers(AiProfile p) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${p.key}',
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

  static Future<String> _chat(AiProfile p, String system, String user) async {
    try {
      final r = await http
          .post(
            _uri(p, '/chat/completions'),
            headers: _headers(p),
            body: jsonEncode({
              'model': p.model,
              'temperature': 0.3,
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) throw _httpError(r.statusCode);
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final first = (data['choices'] as List<dynamic>).first as Map<String, dynamic>;
      final text = ((first['message'] as Map<String, dynamic>)['content'] as String).trim();
      if (text.isEmpty) throw ApiException('پاسخ خالی از سرویس AI دریافت شد.');
      return text;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
          'اتصال به سرویس AI ممکن نشد. اینترنت، آدرس و دسترسی منطقه‌ای سرویس را بررسی کنید.');
    }
  }

  /// پرسش از AIهای تنظیم‌شده.
  /// حالت auto: اولین AI آماده؛ اگر خطا داد، بعدی. حالت both: همه آماده‌ها برای مقایسه.
  static Future<List<AiAnswer>> ask(
      String cacheKey, String system, String prompt) async {
    final ready = [
      for (var i = 0; i < Settings.aiProfiles.length; i++)
        if (Settings.aiProfiles[i].ready) i
    ];
    if (ready.isEmpty) {
      throw ApiException('ابتدا در تنظیمات، حداقل یک AI را (آدرس، مدل و کلید) وارد کنید.');
    }

    Future<AiAnswer> one(int i) async {
      final p = Settings.aiProfiles[i];
      final label = p.label(i);
      final key = '$cacheKey|$i|${p.model}';
      final cached = _cache[key];
      if (cached != null) return AiAnswer(label, p.model, cached, true);
      try {
        final text = await _chat(p, system, prompt);
        _cache[key] = text;
        return AiAnswer(label, p.model, text, true);
      } on ApiException catch (e) {
        return AiAnswer(label, p.model, e.message, false);
      }
    }

    if (Settings.aiMode == 'both') {
      final all = await Future.wait(ready.map(one));
      if (all.every((a) => !a.ok)) {
        throw ApiException(all.map((a) => '${a.label}: ${a.text}').join('\n'));
      }
      return all;
    }
    final errors = <String>[];
    for (final i in ready) {
      final a = await one(i);
      if (a.ok) return [a];
      errors.add('${a.label}: ${a.text}');
    }
    throw ApiException(errors.join('\n'));
  }

  /// فهرست مدل‌های در دسترس یک سرویس (برای انتخاب نام درست مدل)
  static Future<List<String>> listModels(AiProfile p) async {
    if (p.baseUrl.isEmpty || p.key.isEmpty) {
      throw ApiException('اول آدرس و کلید را وارد کنید.');
    }
    try {
      final r = await http
          .get(_uri(p, '/models'), headers: _headers(p))
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
