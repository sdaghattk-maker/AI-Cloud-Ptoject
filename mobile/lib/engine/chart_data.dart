import 'dart:math' as math;
import '../models/signal.dart';
import 'analyzer.dart';
import 'backtest.dart';
import 'binance.dart';
import 'decision.dart';
import 'indicators.dart';
import 'strategy.dart';

const chartMaxBars = 1000;

/// علامت یک معامله تاریخی استراتژی منتخب (روی کندل سیگنال)
class ChartMarker {
  final int index, side;
  final double r;
  const ChartMarker(this.index, this.side, this.r);
}

class SrLevel {
  final double price;
  final bool resistance;
  final int touches;
  const SrLevel(this.price, this.resistance, this.touches);
}

/// سطوح ورود/SL/TP که روی چارت رسم می‌شود (سیگنال فعلی یا معامله آزمایشی)
class LevelOverlay {
  final String label;
  final int side, startIndex;
  final double entry, sl, tp1, tp2;
  final bool dashed;
  const LevelOverlay({
    required this.label,
    required this.side,
    required this.startIndex,
    required this.entry,
    required this.sl,
    required this.tp1,
    required this.tp2,
    this.dashed = false,
  });
}

class ChartData {
  final String symbol, timeframe, strategyName;
  final List<int> times;
  final List<double> open, high, low, close, volume;
  final List<double> ema50, ema200, rsi, bbUp, bbLo;
  final List<ChartMarker> markers;
  final List<SrLevel> levels;
  final AnalyzeResult result;
  final Decision decision;

  const ChartData({
    required this.symbol,
    required this.timeframe,
    required this.strategyName,
    required this.times,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.ema50,
    required this.ema200,
    required this.rsi,
    required this.bbUp,
    required this.bbLo,
    required this.markers,
    required this.levels,
    required this.result,
    required this.decision,
  });

  int get length => close.length;

  /// سطوح سیگنال فعلی (اگر وجود داشته باشد)
  LevelOverlay? get liveOverlay {
    final s = result.signal;
    if (s == null || length == 0) return null;
    return LevelOverlay(
      label: 'سیگنال',
      side: s.isLong ? 1 : -1,
      startIndex: length - 1,
      entry: s.entry,
      sl: s.sl,
      tp1: s.tp1,
      tp2: s.tp2,
    );
  }
}

/// اولین اندیسی که زمانش ≥ ms است؛ اگر همه زمان‌ها کوچک‌ترند -1
int indexOfTime(List<int> times, int ms) {
  for (var i = 0; i < times.length; i++) {
    if (times[i] >= ms) return i;
  }
  return -1;
}

/// سطوح حمایت/مقاومت از پیوت‌های اخیر: پیوت‌های نزدیک خوشه‌بندی می‌شوند و
/// فقط سطوحی که حداقل دو بار لمس شده‌اند می‌مانند. حداکثر ۲ سطح بالا و ۲ سطح پایین قیمت.
List<SrLevel> findSrLevels(List<double> high, List<double> low, double lastPrice,
    double atr,
    {int lookback = 300, int k = 4}) {
  final n = high.length;
  if (n < 2 * k + 3) return const [];
  final from = math.max(k, n - lookback);
  final pivots = <double>[];
  for (var i = from; i < n - k; i++) {
    var isHigh = true, isLow = true;
    for (var j = i - k; j <= i + k; j++) {
      if (j == i) continue;
      if (high[j] > high[i]) isHigh = false;
      if (low[j] < low[i]) isLow = false;
    }
    if (isHigh) pivots.add(high[i]);
    if (isLow) pivots.add(low[i]);
  }
  if (pivots.isEmpty) return const [];
  pivots.sort();
  final tol = math.max(atr * 0.6, lastPrice * 0.002);

  final clusters = <(double, int)>[]; // (میانگین، تعداد لمس)
  var sum = pivots.first, cnt = 1;
  for (var i = 1; i < pivots.length; i++) {
    final avg = sum / cnt;
    if (pivots[i] - avg <= tol) {
      sum += pivots[i];
      cnt++;
    } else {
      clusters.add((sum / cnt, cnt));
      sum = pivots[i];
      cnt = 1;
    }
  }
  clusters.add((sum / cnt, cnt));

  final strong = clusters.where((c) => c.$2 >= 2).toList();
  final above = strong.where((c) => c.$1 > lastPrice).toList()
    ..sort((a, b) => (a.$1 - lastPrice).compareTo(b.$1 - lastPrice));
  final below = strong.where((c) => c.$1 <= lastPrice).toList()
    ..sort((a, b) => (lastPrice - a.$1).compareTo(lastPrice - b.$1));
  return [
    for (final c in above.take(2)) SrLevel(c.$1, true, c.$2),
    for (final c in below.take(2)) SrLevel(c.$1, false, c.$2),
  ];
}

ChartData buildChartData(String symbol, String tf, Candles c, SeriesResult series,
    AnalyzeResult applied) {
  final n = c.length;
  final d = computeIndicators(c);
  final from = math.max(0, n - chartMaxBars);
  List<double> cut(List<double> a) => a.sublist(from);

  final params = series.params;
  var markers = <ChartMarker>[];
  if (params != null && n > 250) {
    final trades = runBacktest(d, buildFor(d, params), params, 200, n);
    markers = [
      for (final t in trades)
        if (t.bar >= from) ChartMarker(t.bar - from, t.side, t.r)
    ];
  }
  final high = cut(c.high), low = cut(c.low);
  final levels = n == 0
      ? <SrLevel>[]
      : findSrLevels(high, low, c.close[n - 1], d.atr[n - 1]);

  return ChartData(
    symbol: symbol,
    timeframe: tf,
    strategyName: params?.strategyName ?? '',
    times: c.times.sublist(from),
    open: cut(c.open),
    high: high,
    low: low,
    close: cut(c.close),
    volume: cut(c.volume),
    ema50: cut(d.ema50),
    ema200: cut(d.ema200),
    rsi: cut(d.rsi),
    bbUp: cut(d.bbUp),
    bbLo: cut(d.bbLo),
    markers: markers,
    levels: levels,
    result: applied,
    decision: decisionForResult(applied),
  );
}
