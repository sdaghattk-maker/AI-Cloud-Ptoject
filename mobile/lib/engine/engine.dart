import '../ml/ml_filter.dart';
import '../paper/paper_store.dart';
import '../research/daily.dart';
import '../research/report.dart';
import '../models/signal.dart';
import '../services/errors.dart';
import '../services/settings.dart';
import 'analyzer.dart';
import 'binance.dart';
import 'chart_data.dart';

/// اسکن پیش‌فرض فقط ۴ ساعته و روزانه است: در گزارش پژوهشی، ۱۵ دقیقه و ۱ ساعت هزینه (۰.۱۶ تا ۰.۲۰R)
/// را بیش از هر لبه‌ای می‌خورند و حتی خام هم لبه معناداری نداشتند.
const defaultTimeframes = ['4h', '1d'];

/// گزارش پژوهشی کامل همه تایم‌فریم‌ها را بررسی می‌کند.
const allTimeframes = ['15m', '1h', '4h', '1d'];

class ResearchData {
  final List<SeriesReport> rows;
  final List<String> failures;
  const ResearchData(this.rows, this.failures);
}

class DailyData {
  final List<DailySeries> rows;
  final List<String> failures;
  const DailyData(this.rows, this.failures);
}

class Engine {
  /// اعمال فیلتر ML روی نتیجه یک سری:
  /// - مدل «تأییدشده» و احتمال کمتر از آستانه → سیگنال رد می‌شود
  /// - مدل تأییدنشده → فقط به‌عنوان اطلاعات نمایش داده می‌شود
  static AnalyzeResult applyMl(SeriesResult s, MlModel? model) {
    final r = s.result;
    final sig = r.signal;
    final x = s.liveX;
    if (sig == null || x == null) return r;

    AnalyzeResult build(Signal? ns, String note) => AnalyzeResult(
        symbol: r.symbol,
        timeframe: r.timeframe,
        candles: r.candles,
        edgeOk: r.edgeOk,
        backtest: r.backtest,
        signal: ns,
        note: note,
        context: r.context);

    if (model == null) {
      final u = sig.copyWith(
          mlStatus: 'فیلتر ML هنوز آموزش ندیده؛ یک‌بار «اسکن بازار» را اجرا کنید.');
      return build(u.copyWith(explanation: explanationFor(u)), '');
    }

    final prob = model.model.predict(x);
    final pct = (prob * 100).round();
    final thrPct = (model.threshold * 100).round();

    if (model.approved && prob < model.threshold) {
      return build(
          null,
          'سیگنال پایه وجود داشت ولی فیلتر ML آن را رد کرد '
          '(احتمال موفقیت $pct٪ کمتر از آستانه $thrPct٪).');
    }
    final status = model.approved
        ? 'تأیید ML (احتمال موفقیت $pct٪، آستانه $thrPct٪).'
        : 'ML فقط اطلاعاتی است و در بک‌تست برتری معنادار نشان نداده (احتمال $pct٪).';
    final u = sig.copyWith(mlProb: prob, mlStatus: status, mlApproved: model.approved);
    return build(u.copyWith(explanation: explanationFor(u)), '');
  }

  static Future<AnalyzeResult> analyze(String symbol, String tf) async {
    final sym = symbol.toUpperCase();
    final candles = await Binance.klines(sym, tf);
    final series = analyzeSeries(sym, tf, candles);
    final model = await MlStore.load(tf);
    final applied = applyMl(series, model);
    await _record(applied.signal);
    return applied;
  }

  /// ثبت سیگنال برای Paper Trading؛ هیچ‌وقت نباید تحلیل را خراب کند.
  static Future<void> _record(Signal? s) async {
    if (s == null) return;
    try {
      await PaperStore.record(s);
    } catch (_) {}
  }

  /// داده کامل چارت: کندل‌ها، اندیکاتورها، سطوح، علامت معاملات تاریخی و حکم تصمیم
  static Future<ChartData> chart(String symbol, String tf) async {
    final sym = symbol.toUpperCase();
    final candles = await Binance.klines(sym, tf);
    await Future<void>.delayed(Duration.zero); // اجازه به UI برای نمایش «در حال بارگذاری»
    final series = analyzeSeries(sym, tf, candles);
    final model = await MlStore.load(tf);
    final applied = applyMl(series, model);
    await _record(applied.signal);
    return buildChartData(sym, tf, candles, series, applied);
  }

  /// اسکن چند نماد و چند تایم‌فریم. بعد از دریافت همه داده‌ها، برای هر تایم‌فریم
  /// یک مدل ML از معاملات تاریخی همه نمادها آموزش می‌بیند و روی سیگنال‌ها اعمال می‌شود.
  static Future<List<Signal>> scan({
    List<String>? symbols,
    List<String>? timeframes,
    void Function(int done, int total)? onProgress,
  }) async {
    final syms = symbols ?? Settings.symbols;
    final tfs = timeframes ?? defaultTimeframes;
    final total = syms.length * tfs.length;
    var done = 0, failed = 0;
    String? firstError;
    final all = <MapEntry<String, SeriesResult>>[];
    onProgress?.call(0, total);

    for (final s in syms) {
      final results = await Future.wait(
          tfs.map<Future<MapEntry<String, SeriesResult>?>>((tf) async {
        try {
          final c = await Binance.klines(s, tf);
          return MapEntry(tf, analyzeSeries(s, tf, c));
        } catch (e) {
          failed++;
          firstError ??= e.toString();
          return null;
        }
      }));
      for (final r in results) {
        if (r != null) all.add(r);
      }
      done += tfs.length;
      onProgress?.call(done, total);
      await Future<void>.delayed(Duration.zero); // اجازه به UI برای رفرش
    }
    if (failed == total && firstError != null) {
      throw ApiException(firstError!);
    }

    final models = <String, MlModel?>{};
    for (final tf in tfs) {
      final pooled = [
        for (final e in all)
          if (e.key == tf) ...e.value.samples
      ];
      var m = buildMlModel(pooled);
      if (m != null) {
        await MlStore.save(tf, m);
      } else {
        m = await MlStore.load(tf); // نمونه کافی نبود؛ از مدل قبلی استفاده کن
      }
      models[tf] = m;
    }

    final out = <Signal>[];
    for (final e in all) {
      final r = applyMl(e.value, models[e.key]);
      if (r.signal != null) out.add(r.signal!);
    }
    for (final sg in out) {
      await _record(sg);
    }
    out.sort((a, b) {
      final c = b.backtest.expectancyR.compareTo(a.backtest.expectancyR);
      return c != 0 ? c : b.score.compareTo(a.score);
    });
    return out;
  }

  /// تحلیل همه نمادها × تایم‌فریم‌ها فقط برای پژوهش (چیزی ثبت نمی‌کند و ML را درگیر نمی‌کند).
  static Future<ResearchData> research({
    List<String>? symbols,
    List<String>? timeframes,
    void Function(int done, int total)? onProgress,
  }) async {
    final syms = symbols ?? Settings.symbols;
    final tfs = timeframes ?? allTimeframes;
    final total = syms.length * tfs.length;
    var done = 0;
    final rows = <SeriesReport>[];
    final failures = <String>[];
    onProgress?.call(0, total);

    for (final s in syms) {
      final fetched = await Future.wait(tfs.map<Future<Candles?>>((tf) async {
        try {
          return await Binance.klines(s, tf);
        } catch (e) {
          failures.add('$s $tf: $e');
          return null;
        }
      }));
      for (var k = 0; k < tfs.length; k++) {
        final c = fetched[k];
        if (c != null && c.length >= 2) {
          try {
            final series = analyzeSeries(s, tfs[k], c);
            final p = series.params;
            rows.add(SeriesReport(
              symbol: s,
              timeframe: tfs[k],
              strategyName: p == null ? '' : famName(p.strategy),
              candles: c.length,
              firstMs: c.times.first,
              lastMs: c.times.last,
              changePct: (c.close.last / c.close.first - 1) * 100,
              result: series.result,
              oos: series.oos,
              samples: series.samples,
            ));
          } catch (e) {
            failures.add('$s ${tfs[k]}: analysis error $e');
          }
        }
        done++;
        onProgress?.call(done, total);
        await Future<void>.delayed(Duration.zero); // اجازه به UI برای رفرش
      }
    }
    if (rows.isEmpty && failures.isNotEmpty) throw ApiException(failures.first);
    return ResearchData(rows, failures);
  }

  /// اعتبارسنجی متمرکز شکست کانال روی روزانه (پارامتر ثابت) برای همه نمادهای تنظیمات.
  static Future<DailyData> dailyValidation({
    void Function(int done, int total)? onProgress,
  }) async {
    final syms = Settings.symbols;
    final rows = <DailySeries>[];
    final failures = <String>[];
    onProgress?.call(0, syms.length);
    var done = 0;
    for (final s in syms) {
      try {
        final c = await Binance.klines(s, '1d');
        if (c.length < 300) {
          failures.add('$s: کمتر از ۳۰۰ کندل روزانه');
        } else {
          rows.add(analyzeDaily(s, c));
        }
      } catch (e) {
        failures.add('$s: $e');
      }
      done++;
      onProgress?.call(done, syms.length);
      await Future<void>.delayed(Duration.zero);
    }
    if (rows.isEmpty && failures.isNotEmpty) throw ApiException(failures.first);
    return DailyData(rows, failures);
  }
}
