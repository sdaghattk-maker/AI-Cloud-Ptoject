import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptosignal/engine/analyzer.dart';
import 'package:cryptosignal/engine/binance.dart';
import 'package:cryptosignal/engine/chart_data.dart';
import 'package:cryptosignal/engine/engine.dart';
import 'package:cryptosignal/widgets/candle_chart.dart';

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
    times.add(1700000000000 + i * 3600000);
    o.add(open);
    c.add(price);
    h.add(max(open, price) * (1 + (gauss() * 0.003).abs()));
    l.add(min(open, price) * (1 - (gauss() * 0.003).abs()));
    v.add(exp(10 + gauss() * 0.4));
  }
  return Candles(times, o, h, l, c, v);
}

ChartData buildSynthetic() {
  final c = synthetic(5000, 7);
  final series = analyzeSeries('TESTUSDT', '1h', c);
  final applied = Engine.applyMl(series, null);
  return buildChartData('TESTUSDT', '1h', c, series, applied);
}

void main() {
  test('findSrLevels finds repeated resistance above and support below', () {
    const n = 120;
    final high = List<double>.filled(n, 100.5);
    final low = List<double>.filled(n, 99.5);
    for (final i in [30, 70]) {
      high[i] = 110;
    }
    for (final i in [45, 90]) {
      low[i] = 90;
    }
    final lv = findSrLevels(high, low, 100.0, 1.0);
    expect(lv.any((l) => l.resistance && (l.price - 110).abs() < 0.5), true);
    expect(lv.any((l) => !l.resistance && (l.price - 90).abs() < 0.5), true);
    expect(lv.where((l) => l.resistance).every((l) => l.price > 100), true);
    expect(lv.where((l) => !l.resistance).every((l) => l.price <= 100), true);
    expect(lv.length, lessThanOrEqualTo(4));
  });

  test('findSrLevels handles too little data', () {
    expect(findSrLevels([1, 2, 3], [1, 2, 3], 2, 1), isEmpty);
  });

  test('indexOfTime', () {
    const t = [0, 10, 20];
    expect(indexOfTime(t, 10), 1);
    expect(indexOfTime(t, 5), 1);
    expect(indexOfTime(t, 25), -1);
    expect(indexOfTime(t, -5), 0);
  });

  test('buildChartData: aligned arrays, capped length, valid markers', () {
    final d = buildSynthetic();
    expect(d.length, chartMaxBars);
    for (final a in [d.open, d.high, d.low, d.close, d.volume, d.ema50, d.ema200, d.rsi, d.bbUp, d.bbLo]) {
      expect(a.length, d.length);
    }
    expect(d.times.length, d.length);
    expect(d.markers.every((m) => m.index >= 0 && m.index < d.length), true);
    expect(d.markers.every((m) => m.side == 1 || m.side == -1), true);
    final live = d.liveOverlay;
    if (live != null) {
      expect(live.startIndex, d.length - 1);
      expect(live.entry, d.result.signal!.entry);
    }
    expect(d.decision.title, isNotEmpty);
  });

  testWidgets('CandleChart paints, taps (crosshair), pans and zooms without errors',
      (tester) async {
    final d = buildSynthetic();
    final last = d.close.last;
    final overlay = LevelOverlay(
      label: 'x',
      side: 1,
      startIndex: d.length - 5,
      entry: last,
      sl: last * 0.98,
      tp1: last * 1.02,
      tp2: last * 1.04,
    );
    for (final opts in [
      const ChartOptions(),
      const ChartOptions(bb: true),
      const ChartOptions(volume: false, rsi: false, ema50: false, ema200: false),
    ]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 520,
              child: CandleChart(
                  key: UniqueKey(), data: d, overlays: [overlay], options: opts),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);

      await tester.tapAt(tester.getCenter(find.byType(CandleChart)) + const Offset(-40, -60));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(CandleChart), const Offset(150, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(CandleChart), const Offset(-400, 0)); // تا آخرین کندل برگرد
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
