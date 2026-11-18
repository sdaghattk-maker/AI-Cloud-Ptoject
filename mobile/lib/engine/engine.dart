import '../models/signal.dart';
import '../services/errors.dart';
import '../services/settings.dart';
import 'analyzer.dart';
import 'binance.dart';

const defaultTimeframes = ['15m', '1h', '4h', '1d'];

class Engine {
  static Future<AnalyzeResult> analyze(String symbol, String tf) async {
    final candles = await Binance.klines(symbol.toUpperCase(), tf);
    return analyzeCandles(symbol.toUpperCase(), tf, candles);
  }

  /// اسکن چند نماد و چند تایم‌فریم؛ نتایج بر اساس کیفیت مرتب می‌شوند.
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
    final out = <Signal>[];
    onProgress?.call(0, total);

    for (final s in syms) {
      final results = await Future.wait(tfs.map((tf) async {
        try {
          return (await analyze(s, tf)).signal;
        } catch (e) {
          failed++;
          firstError ??= e.toString();
          return null;
        }
      }));
      for (final r in results) {
        if (r != null) out.add(r);
      }
      done += tfs.length;
      onProgress?.call(done, total);
      await Future<void>.delayed(Duration.zero); // اجازه به UI برای رفرش
    }
    if (failed == total && firstError != null) {
      throw ApiException(firstError!);
    }
    out.sort((a, b) {
      final c = b.backtest.expectancyR.compareTo(a.backtest.expectancyR);
      return c != 0 ? c : b.score.compareTo(a.score);
    });
    return out;
  }
}
