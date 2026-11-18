import 'dart:math' as math;
import '../ml/features.dart';
import '../ml/ml_filter.dart';
import '../models/signal.dart';
import 'backtest.dart';
import 'binance.dart';
import 'indicators.dart';
import 'strategy.dart';

const adxGrid = [15.0, 20.0, 25.0];
const slGrid = [1.2, 1.5, 2.0];
const rrGrid = [2.0, 3.0];

const minOosTrades = 20;
const minOosExpectancy = 0.0;
const minProfitFactor = 1.1;

Params? _optimize(Indicators d, Map<double, Signals> sigs, int start, int end,
    {int minTrades = 10}) {
  Params? best;
  var bestScore = -1e9;
  for (final adx in adxGrid) {
    for (final sl in slGrid) {
      for (final rr in rrGrid) {
        final p = Params(adx, sl, rr);
        final st = statsOf(runBacktest(d, sigs[adx]!, p, start, end));
        if (st.trades < minTrades) continue;
        // امتیاز با جریمه تعداد کم معامله (جلوگیری از overfitting)
        final score = st.expectancyR * math.sqrt(st.trades);
        if (score > bestScore) {
          best = p;
          bestScore = score;
        }
      }
    }
  }
  return best;
}

String explanationFor(Signal s) {
  final dir = s.isLong ? 'خرید (Long)' : 'فروش (Short)';
  final b = s.backtest;
  final ml = s.mlStatus.isEmpty ? '' : ' ${s.mlStatus}';
  return '${s.symbol} در تایم‌فریم ${s.timeframe} سیگنال $dir دارد؛ روند و مومنتوم هم‌جهت‌اند. '
      'ورود ${fmt(s.entry)}، حد ضرر ${fmt(s.sl)}، هدف‌ها ${fmt(s.tp1)} و ${fmt(s.tp2)}. '
      'در آزمون خارج از نمونه: ${b.trades} معامله، وین‌ریت ${b.winRate}٪، '
      'میانگین ${b.expectancyR}R.$ml '
      'این تحلیل توصیه مالی نیست؛ ریسک هر معامله را کوچک نگه دارید.';
}

/// نتیجه تحلیل یک سری + داده‌های لازم برای آموزش/اعمال فیلتر ML
class SeriesResult {
  final AnalyzeResult result;
  final List<TradeSample> samples; // معاملات تاریخی با ویژگی‌هایشان
  final List<double>? liveX; // ویژگی‌های سیگنال فعلی (اگر باشد)
  const SeriesResult(this.result, this.samples, this.liveX);
}

double _r2(double v) => (v * 100).round() / 100;

/// نمونه‌های آموزشی ML: همه سیگنال‌های ورودِ منعطف (adx≥15) با پارامترهای مرجع
List<TradeSample> _collectSamples(Indicators d, Candles c, Map<double, Signals> sigs) {
  final n = c.length;
  const ref = Params(15, 1.5, 2.0);
  final trades = runBacktest(d, sigs[15.0]!, ref, 200, n);
  return [
    for (final t in trades)
      TradeSample(
        timeMs: c.times[t.bar],
        endMs: c.times[math.min(t.bar + t.bars, n - 1)],
        x: featuresAt(d, t.bar, t.side),
        r: t.r,
      )
  ];
}

SeriesResult analyzeSeries(String symbol, String tf, Candles c) {
  const train = 2000, test = 500;
  final n = c.length;
  final d = computeIndicators(c);
  final sigs = {for (final a in adxGrid) a: buildSignals(d, a)};
  final samples = n >= 250 ? _collectSamples(d, c, sigs) : <TradeSample>[];

  final oosTrades = <Trade>[];
  var start = 200;
  while (start + train + test <= n) {
    final p = _optimize(d, sigs, start, start + train);
    if (p != null) {
      oosTrades.addAll(
          runBacktest(d, sigs[p.adxMin]!, p, start + train, start + train + test));
    }
    start += test;
  }
  final oos = statsOf(oosTrades);
  final finalP = _optimize(d, sigs, math.max(200, n - train), n);

  SeriesResult out(bool edge, Signal? s, List<double>? x) => SeriesResult(
      AnalyzeResult(
          symbol: symbol,
          timeframe: tf,
          candles: n,
          edgeOk: edge,
          backtest: oos,
          signal: s),
      samples,
      x);

  if (finalP == null || n < 250) return out(false, null, null);

  final edgeOk = oos.trades >= minOosTrades &&
      oos.expectancyR > minOosExpectancy &&
      oos.profitFactor >= minProfitFactor;

  final sig = sigs[finalP.adxMin]!;
  final last = n - 1;
  final side = sig.side[last];
  if (side == 0 || !edgeOk) return out(edgeOk, null, null);

  final entry = c.close[last];
  final atr = d.atr[last];
  final risk = finalP.atrSl * atr;
  final base = Signal(
    symbol: symbol,
    timeframe: tf,
    side: side == 1 ? 'LONG' : 'SHORT',
    time: DateTime.fromMillisecondsSinceEpoch(c.times[last], isUtc: true)
        .toIso8601String(),
    explanation: '',
    score: sig.score[last],
    entry: entry,
    sl: entry - side * risk,
    tp1: entry + side * risk * rr1,
    tp2: entry + side * risk * finalP.rr2,
    riskPct: risk / entry * 100,
    backtest: oos,
    context: {
      'adx': _r2(d.adx[last]),
      'rsi': _r2(d.rsi[last]),
      'volRatio': _r2(d.volRatio[last]),
      'atrPercent': _r2(atr / entry * 100),
      'distFromEma50InAtr': _r2((entry - d.ema50[last]) / atr),
      'ema50VsEma200Percent': _r2((d.ema50[last] - d.ema200[last]) / d.ema200[last] * 100),
    },
  );
  final signal = base.copyWith(explanation: explanationFor(base));
  return out(true, signal, featuresAt(d, last, side));
}

/// سازگار با نسخه قبل (بدون ML)
AnalyzeResult analyzeCandles(String symbol, String tf, Candles c) =>
    analyzeSeries(symbol, tf, c).result;
