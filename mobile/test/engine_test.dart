import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptosignal/engine/analyzer.dart';
import 'package:cryptosignal/engine/backtest.dart';
import 'package:cryptosignal/engine/binance.dart';
import 'package:cryptosignal/engine/indicators.dart';
import 'package:cryptosignal/engine/strategy.dart';

Candles synthetic(int n, int seed, {double vol = 0.006}) {
  final rnd = Random(seed);
  double gauss() {
    final u1 = 1 - rnd.nextDouble();
    final u2 = rnd.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  final times = <int>[], o = <double>[], h = <double>[], l = <double>[];
  final c = <double>[], v = <double>[];
  var price = 100.0, drift = 0.0;
  for (var i = 0; i < n; i++) {
    if (i % 250 == 0) drift = gauss() * 0.0012 * vol / 0.006;
    final open = price;
    price = price * exp(drift + gauss() * vol);
    times.add(i * 3600000);
    o.add(open);
    c.add(price);
    h.add(max(open, price) * (1 + (gauss() * 0.003 * vol / 0.006).abs()));
    l.add(min(open, price) * (1 - (gauss() * 0.003 * vol / 0.006).abs()));
    v.add(exp(10 + gauss() * 0.4));
  }
  return Candles(times, o, h, l, c, v);
}

Candles cut(Candles c, int n) => Candles(
      c.times.sublist(0, n),
      c.open.sublist(0, n),
      c.high.sublist(0, n),
      c.low.sublist(0, n),
      c.close.sublist(0, n),
      c.volume.sublist(0, n),
    );

void main() {
  test('EMA of a constant series stays constant', () {
    final e = ema(List<double>.filled(100, 5.0), 21);
    expect(e.last, closeTo(5.0, 1e-9));
  });

  test('indicators are finite and in range', () {
    final d = computeIndicators(synthetic(600, 1));
    expect(d.atr.last, greaterThan(0));
    expect(d.rsi.every((x) => x >= 0 && x <= 100), true);
    expect(d.adx.every((x) => x >= 0 && x <= 100.0001), true);
  });

  test('signals have no look-ahead', () {
    final full = synthetic(1500, 3);
    final a = buildSignals(computeIndicators(full), 20).side;
    final b = buildSignals(computeIndicators(cut(full, 1000)), 20).side;
    expect(a.sublist(0, 1000), b);
  });

  test('backtest runs and stats are sane', () {
    final c = synthetic(5000, 7);
    final d = computeIndicators(c);
    const p = Params(15, 1.5, 2.0);
    final tr = runBacktest(d, buildSignals(d, 15), p, 200, 5000);
    final st = statsOf(tr);
    expect(st.trades, greaterThan(0));
    expect(st.expectancyR, inInclusiveRange(-1.5, 3.0));
  });

  test('analyzeCandles returns a well-formed result', () {
    final r = analyzeCandles('TESTUSDT', '1h', synthetic(5000, 7));
    expect(r.symbol, 'TESTUSDT');
    expect(r.candles, 5000);
    expect(r.context['lastPrice'], greaterThan(0));
    expect(r.backtest.trades, greaterThanOrEqualTo(0));
    if (r.signal != null) {
      expect(r.edgeOk, true);
      expect(r.signal!.explanation, isNotEmpty);
    }
  });

  test('all strategy builders are causal (no look-ahead)', () {
    final full = synthetic(1500, 3);
    for (final p in [
      const Params(20, 1.5, 2.0),
      const Params(0, 1.5, 2.0, strategy: 1, param: 20),
      const Params(0, 1.5, 2.0, strategy: 1, param: 50),
      const Params(0, 1.5, 2.0, strategy: 2, param: 30),
    ]) {
      final a = buildFor(computeIndicators(full), p).side;
      final b = buildFor(computeIndicators(cut(full, 1000)), p).side;
      expect(a.sublist(0, 1000), b, reason: 'strategy ${p.key}');
    }
  });

  test('param grid has 42 combos over 7 distinct signal sets', () {
    expect(paramGrid.length, 42);
    expect(paramGrid.map((p) => p.key).toSet().length, 7);
    expect(paramGrid.where((p) => p.strategy == 1).length, 12);
    expect(paramGrid.where((p) => p.strategy == 2).length, 12);
  });

  test('cost filter: round-trip costs vs risk', () {
    expect(costInR(100, 0.5), greaterThan(maxCostR)); // stop 0.5% -> too costly
    expect(costInR(100, 2.0), lessThanOrEqualTo(maxCostR)); // stop 2% -> fine
    expect(costInR(100, 0), double.infinity);
  });

  test('backtest skips every signal when costs dominate (tiny volatility)', () {
    final c = synthetic(1000, 5, vol: 0.0005);
    final d = computeIndicators(c);
    final side = List<int>.filled(1000, 0);
    for (var i = 300; i < 900; i += 50) {
      side[i] = 1;
    }
    final sig = Signals(side, List<double>.filled(1000, 50));
    final tr = runBacktest(d, sig, const Params(15, 1.5, 2.0), 200, 1000);
    expect(tr, isEmpty);
  });

  test('statsOf reports a positive t-stat for consistently positive R', () {
    final tr = [
      for (var i = 0; i < 40; i++) Trade(i.isEven ? 1.0 : 0.6, i, 1, 5),
    ];
    final st = statsOf(tr);
    expect(st.tStat, greaterThan(5));
    expect(statsOf(const []).tStat, 0);
  });

  test('every produced signal names its strategy and passes the cost filter', () {
    final r = analyzeCandles('TESTUSDT', '1h', synthetic(5000, 7));
    final s = r.signal;
    if (s != null) {
      expect(strategyNames, contains(s.strategy));
      expect(costInR(s.entry, (s.entry - s.sl).abs()), lessThanOrEqualTo(maxCostR));
    }
  });

  test('trades carry cost in R and stop size consistent with the cost model', () {
    final c = synthetic(5000, 7);
    final d = computeIndicators(c);
    const p = Params(15, 1.5, 2.0);
    final tr = runBacktest(d, buildSignals(d, 15), p, 200, 5000);
    expect(tr, isNotEmpty);
    for (final t in tr) {
      expect(t.costR, greaterThan(0));
      expect(t.costR, lessThanOrEqualTo(maxCostR + 0.01));
      expect(t.riskPct, greaterThan(0));
      // هزینه (R) × اندازه حد ضرر (کسر قیمت) = هزینه رفت‌وبرگشت + لغزش
      expect(t.costR * t.riskPct / 100, closeTo(fee * 2 + slippage, 1e-5));
    }
  });
}
