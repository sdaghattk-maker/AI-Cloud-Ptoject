import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptosignal/engine/analyzer.dart';
import 'package:cryptosignal/engine/backtest.dart';
import 'package:cryptosignal/engine/binance.dart';
import 'package:cryptosignal/engine/indicators.dart';
import 'package:cryptosignal/engine/strategy.dart';

Candles synthetic(int n, int seed) {
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
    if (i % 250 == 0) drift = gauss() * 0.0012;
    final open = price;
    price = price * exp(drift + gauss() * 0.006);
    times.add(i * 3600000);
    o.add(open);
    c.add(price);
    h.add(max(open, price) * (1 + (gauss() * 0.003).abs()));
    l.add(min(open, price) * (1 - (gauss() * 0.003).abs()));
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
    expect(r.backtest.trades, greaterThanOrEqualTo(0));
    if (r.signal != null) {
      expect(r.edgeOk, true);
      expect(r.signal!.explanation, isNotEmpty);
    }
  });
}
