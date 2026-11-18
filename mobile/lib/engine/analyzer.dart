import 'dart:math' as math;
import '../ml/features.dart';
import '../ml/ml_filter.dart';
import '../models/signal.dart';
import 'backtest.dart';
import 'binance.dart';
import 'indicators.dart';
import 'strategy.dart';

const adxGrid = [15.0, 20.0, 25.0]; // استراتژی ۰: حداقل ADX
const breakoutGrid = [20, 50]; // استراتژی ۱: طول کانال
const reversionGrid = [22.0, 30.0]; // استراتژی ۲: سقف ADX (بازار رنج)
const slGrid = [1.2, 1.5, 2.0];
const rrGrid = [2.0, 3.0];

const minOosTrades = 20;
const minOosExpectancy = 0.0;
const minProfitFactor = 1.1;
const minOosTStat = 1.5; // با چند استراتژی و چند سری، آستانه معناداری لازم است

/// همه ترکیب‌های قابل انتخاب (۴۲ ترکیب). انتخاب فقط روی داده آموزش انجام می‌شود.
final List<Params> paramGrid = [
  for (final a in adxGrid)
    for (final sl in slGrid)
      for (final rr in rrGrid) Params(a, sl, rr),
  for (final lb in breakoutGrid)
    for (final sl in slGrid)
      for (final rr in rrGrid) Params(0, sl, rr, strategy: 1, param: lb.toDouble()),
  for (final am in reversionGrid)
    for (final sl in slGrid)
      for (final rr in rrGrid) Params(0, sl, rr, strategy: 2, param: am),
];

/// پارامترهای مرجع برای ساخت نمونه‌های آموزشی ML (منعطف‌ترین نسخه هر استراتژی)
const _refParams = [
  Params(15, 1.5, 2.0),
  Params(0, 1.5, 2.0, strategy: 1, param: 20),
  Params(0, 1.5, 2.0, strategy: 2, param: 30),
];

Params? _optimize(Indicators d, Map<String, Signals> bank, int start, int end,
    {int minTrades = 10}) {
  Params? best;
  var bestScore = -1e9;
  for (final p in paramGrid) {
    final st = statsOf(runBacktest(d, bank[p.key]!, p, start, end));
    if (st.trades < minTrades) continue;
    // امتیاز با جریمه تعداد کم معامله (جلوگیری از overfitting)
    final score = st.expectancyR * math.sqrt(st.trades);
    if (score > bestScore) {
      best = p;
      bestScore = score;
    }
  }
  return best;
}

String explanationFor(Signal s) {
  final dir = s.isLong ? 'خرید (Long)' : 'فروش (Short)';
  final b = s.backtest;
  final ml = s.mlStatus.isEmpty ? '' : ' ${s.mlStatus}';
  final st = s.strategy.isEmpty ? '' : ' (استراتژی: ${s.strategy})';
  return '${s.symbol} در تایم‌فریم ${s.timeframe} سیگنال $dir دارد$st. '
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

double _r2(double v) => v.isNaN || v.isInfinite ? 0 : (v * 100).round() / 100;

/// عکس لحظه‌ای اندیکاتورها در یک کندل (برای نمایش به AI)
Map<String, double> _contextAt(Indicators d, Candles c, int i) {
  final price = c.close[i];
  final atr = d.atr[i];
  return {
    'lastPrice': price,
    'adx': _r2(d.adx[i]),
    'rsi': _r2(d.rsi[i]),
    'volRatio': _r2(d.volRatio[i]),
    'atrPercent': _r2(price > 0 ? atr / price * 100 : 0),
    'distFromEma50InAtr': _r2(atr > 0 ? (price - d.ema50[i]) / atr : 0),
    'ema50VsEma200Percent':
        _r2(d.ema200[i] > 0 ? (d.ema50[i] - d.ema200[i]) / d.ema200[i] * 100 : 0),
  };
}

/// نمونه‌های آموزشی ML: معاملات تاریخی هر سه استراتژی با پارامتر مرجع
List<TradeSample> _collectSamples(Indicators d, Candles c, Map<String, Signals> bank) {
  final n = c.length;
  final out = <TradeSample>[];
  for (final ref in _refParams) {
    final trades = runBacktest(d, bank[ref.key]!, ref, 200, n);
    for (final t in trades) {
      out.add(TradeSample(
        timeMs: c.times[t.bar],
        endMs: c.times[math.min(t.bar + t.bars, n - 1)],
        x: featuresAt(d, t.bar, t.side, strategy: ref.strategy),
        r: t.r,
      ));
    }
  }
  return out;
}

SeriesResult analyzeSeries(String symbol, String tf, Candles c) {
  const train = 2000, test = 500;
  final n = c.length;
  final d = computeIndicators(c);
  final bank = <String, Signals>{};
  for (final p in paramGrid) {
    bank.putIfAbsent(p.key, () => buildFor(d, p));
  }
  final samples = n >= 250 ? _collectSamples(d, c, bank) : <TradeSample>[];
  final ctx = n == 0 ? <String, double>{} : _contextAt(d, c, n - 1);

  final oosTrades = <Trade>[];
  var start = 200;
  while (start + train + test <= n) {
    final p = _optimize(d, bank, start, start + train);
    if (p != null) {
      oosTrades.addAll(
          runBacktest(d, bank[p.key]!, p, start + train, start + train + test));
    }
    start += test;
  }
  final oos = statsOf(oosTrades);
  final finalP = _optimize(d, bank, math.max(200, n - train), n);

  SeriesResult out(bool edge, Signal? s, List<double>? x, {String note = ''}) =>
      SeriesResult(
          AnalyzeResult(
              symbol: symbol,
              timeframe: tf,
              candles: n,
              edgeOk: edge,
              backtest: oos,
              signal: s,
              note: note,
              context: ctx),
          samples,
          x);

  if (finalP == null || n < 250) return out(false, null, null);

  final edgeOk = oos.trades >= minOosTrades &&
      oos.expectancyR > minOosExpectancy &&
      oos.profitFactor >= minProfitFactor &&
      oos.tStat >= minOosTStat;

  final sig = bank[finalP.key]!;
  final last = n - 1;
  final side = sig.side[last];
  if (side == 0 || !edgeOk) return out(edgeOk, null, null);

  final entry = c.close[last];
  final atr = d.atr[last];
  final risk = finalP.atrSl * atr;
  final costR = costInR(entry, risk);
  if (costR > maxCostR) {
    return out(
        edgeOk,
        null,
        null,
        note: 'شرط ورود (${finalP.strategyName}) برقرار بود ولی هزینه کارمزد و لغزش '
            '(${(costR * 100).round()}٪ ریسک) از حد مجاز ${(maxCostR * 100).round()}٪ '
            'بیشتر است؛ ورود ارزش ندارد.');
  }

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
    strategy: finalP.strategyName,
    context: ctx,
  );
  final signal = base.copyWith(explanation: explanationFor(base));
  return out(true, signal, featuresAt(d, last, side, strategy: finalP.strategy));
}

/// سازگار با نسخه قبل (بدون ML)
AnalyzeResult analyzeCandles(String symbol, String tf, Candles c) =>
    analyzeSeries(symbol, tf, c).result;
