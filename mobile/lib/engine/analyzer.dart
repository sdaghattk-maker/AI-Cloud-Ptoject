import 'dart:math' as math;
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
  return '${s.symbol} در تایم‌فریم ${s.timeframe} سیگنال $dir دارد؛ روند و مومنتوم هم‌جهت‌اند. '
      'ورود ${fmt(s.entry)}، حد ضرر ${fmt(s.sl)}، هدف‌ها ${fmt(s.tp1)} و ${fmt(s.tp2)}. '
      'در آزمون خارج از نمونه: ${b.trades} معامله، وین‌ریت ${b.winRate}٪، '
      'میانگین ${b.expectancyR}R. این تحلیل توصیه مالی نیست؛ ریسک هر معامله را کوچک نگه دارید.';
}

/// تحلیل کامل: Walk-Forward روی کندل‌های گذشته + سیگنال کندل آخر
AnalyzeResult analyzeCandles(String symbol, String tf, Candles c) {
  const train = 2000, test = 500;
  final n = c.length;
  final d = computeIndicators(c);
  final sigs = {for (final a in adxGrid) a: buildSignals(d, a)};

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

  AnalyzeResult result(bool edge, Signal? s) => AnalyzeResult(
      symbol: symbol,
      timeframe: tf,
      candles: n,
      edgeOk: edge,
      backtest: oos,
      signal: s);

  if (finalP == null || n < 250) return result(false, null);

  final edgeOk = oos.trades >= minOosTrades &&
      oos.expectancyR > minOosExpectancy &&
      oos.profitFactor >= minProfitFactor;

  final sig = sigs[finalP.adxMin]!;
  final last = n - 1;
  final side = sig.side[last];
  if (side == 0 || !edgeOk) return result(edgeOk, null);

  final entry = c.close[last];
  final risk = finalP.atrSl * d.atr[last];
  final s = Signal(
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
  );
  final withText = Signal(
    symbol: s.symbol,
    timeframe: s.timeframe,
    side: s.side,
    time: s.time,
    explanation: explanationFor(s),
    score: s.score,
    entry: s.entry,
    sl: s.sl,
    tp1: s.tp1,
    tp2: s.tp2,
    riskPct: s.riskPct,
    backtest: s.backtest,
  );
  return result(true, withText);
}
