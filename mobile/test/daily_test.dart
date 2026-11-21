import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptosignal/engine/binance.dart';
import 'package:cryptosignal/engine/engine.dart';
import 'package:cryptosignal/research/daily.dart';

const day = 86400000;

DailyTrade dt(String sym, int entryDay, int exitDay, double r, {int side = 1}) =>
    DailyTrade(
        symbol: sym,
        entryMs: entryDay * day,
        exitMs: exitDay * day,
        side: side,
        r: r,
        cost: 0.03,
        riskPct: 10);

/// سری دست‌ساز: ۱۰۰ معامله، هر ۲۰ روز یکی از ۲۰۱۸، با R های متناوب
DailySeries manual(String sym, double a, double b) {
  final start = DateTime.utc(2018).millisecondsSinceEpoch ~/ day;
  final list = [
    for (var i = 0; i < 100; i++)
      DailyTrade(
          symbol: sym,
          entryMs: (start + i * 20) * day,
          exitMs: (start + i * 20 + 5) * day,
          side: 1,
          r: i.isEven ? a : b,
          cost: 0.03,
          riskPct: 10)
  ];
  return DailySeries(
    symbol: sym,
    candles: 3000,
    firstMs: start * day,
    lastMs: (start + 3000) * day,
    changePct: 100,
    trades: {
      for (final lb in dailyLookbacks)
        for (final sl in dailySls)
          for (final rr in dailyRrs) dailyKey(lb, sl, rr): list
    },
  );
}

Candles dailyCandles(int n, int seed) {
  final rnd = Random(seed);
  double gauss() {
    final u1 = 1 - rnd.nextDouble();
    final u2 = rnd.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  final start = DateTime.utc(2018).millisecondsSinceEpoch;
  final times = <int>[], o = <double>[], h = <double>[], l = <double>[];
  final c = <double>[], v = <double>[];
  var price = 100.0, drift = 0.0;
  for (var i = 0; i < n; i++) {
    if (i % 120 == 0) drift = gauss() * 0.004;
    final open = price;
    price = price * exp(drift + gauss() * 0.03);
    times.add(start + i * day);
    o.add(open);
    c.add(price);
    h.add(max(open, price) * (1 + (gauss() * 0.012).abs()));
    l.add(min(open, price) * (1 - (gauss() * 0.012).abs()));
    v.add(exp(10 + gauss() * 0.4));
  }
  return Candles(times, o, h, l, c, v);
}

void main() {
  group('simulatePortfolio', () {
    final t1 = dt('A', 0, 10, 1.0);
    final t2 = dt('B', 5, 8, 1.0);
    final t3 = dt('C', 12, 20, -1.0);

    test('cap=1 skips the overlapping trade', () {
      final p = simulatePortfolio([t3, t1, t2], cap: 1); // ورودی نامرتب
      expect(p.taken, 2);
      expect(p.skipped, 1);
      expect(p.finalMult, closeTo(1.01 * 0.99, 1e-9));
    });

    test('cap=2 takes all and compounds realised equity', () {
      final p = simulatePortfolio([t1, t2, t3], cap: 2);
      expect(p.taken, 3);
      expect(p.skipped, 0);
      expect(p.finalMult, closeTo(1.02 * 0.99, 1e-9)); // 1.0098
      expect(p.maxDdPct, closeTo(1.0, 0.001));
      expect(p.cagrPct, greaterThan(0));
      expect(p.cagrPct.isFinite, true);
    });

    test('empty input is neutral', () {
      final p = simulatePortfolio(const [], cap: 3);
      expect(p.taken, 0);
      expect(p.finalMult, 1);
    });
  });

  group('dailyChecks', () {
    test('all seven pass for a consistently positive edge', () {
      final rows = [manual('BTCUSDT', 1.0, -0.5), manual('ETHUSDT', 1.0, -0.5)];
      final checks = dailyChecks(rows);
      expect(checks.length, 7);
      for (final c in checks) {
        expect(c.ok, true, reason: c.label);
      }
    });

    test('all fail for a consistently negative result', () {
      final rows = [manual('BTCUSDT', -1.0, 0.3), manual('ETHUSDT', -1.0, 0.3)];
      final checks = dailyChecks(rows);
      for (final c in checks) {
        expect(c.ok, false, reason: c.label);
      }
    });

    test('BTC/ETH check fails when they are absent, others can still pass', () {
      final rows = [manual('AAAUSDT', 1.0, -0.5), manual('BBBUSDT', 1.0, -0.5)];
      final checks = dailyChecks(rows);
      final btc = checks.firstWhere((c) => c.label.contains('BTC'));
      expect(btc.ok, false);
      expect(checks.where((c) => c.ok == true).length, 6);
    });
  });

  group('buildDailyReport', () {
    test('has every section, survivorship warning and exact pass count', () {
      final rep = buildDailyReport(
          [manual('BTCUSDT', 1.0, -0.5), manual('ETHUSDT', 1.0, -0.5)],
          now: DateTime.utc(2026, 11, 20, 8, 0));
      expect(rep, contains('DAILY BREAKOUT VALIDATION 2026-11-20 08:00 UTC'));
      for (final s in ['[1] SCOPE', '[2]', '[3]', '[4]', '[5]', '[6]', '[7] CHECKS']) {
        expect(rep, contains(s));
      }
      expect(rep, contains('SURVIVORSHIP BIAS'));
      expect(rep, contains('positive configs: 12/12'));
      expect(RegExp(r'^  PASS  ', multiLine: true).allMatches(rep).length, 7);
      expect(rep, contains('leave-one-symbol-out'));
      expect(rep, contains('cap=1'));
      expect(rep, contains('long-only cap=3'));
    });

    test('empty input and failures do not crash', () {
      final rep = buildDailyReport(const [], failures: ['BTCUSDT: no network']);
      expect(rep, contains('NO SERIES ANALYSED'));
      expect(rep, contains('no network'));
    });
  });

  group('analyzeDaily', () {
    test('produces all 12 configs with consistent trades', () {
      final s = analyzeDaily('TESTUSDT', dailyCandles(3000, 5));
      expect(s.candles, 3000);
      expect(s.trades.length, 12);
      expect(s.trades.containsKey(dailyRefKey), true);
      for (final list in s.trades.values) {
        for (final t in list) {
          expect(t.exitMs, greaterThanOrEqualTo(t.entryMs));
          expect(t.r.isFinite, true);
          expect(t.cost, greaterThan(0));
        }
      }
    });

    test('too little data gives empty trades, not a crash', () {
      final s = analyzeDaily('TESTUSDT', dailyCandles(200, 5));
      expect(s.trades.values.every((l) => l.isEmpty), true);
    });

    test('a report built from real analysis has no NaN or Infinity', () {
      final rows = [
        analyzeDaily('AAAUSDT', dailyCandles(3000, 5)),
        analyzeDaily('BBBUSDT', dailyCandles(3000, 9)),
      ];
      final rep = buildDailyReport(rows);
      expect(rep, isNot(contains('NaN')));
      expect(rep, isNot(contains('Infinity')));
      expect(dailyChecks(rows).length, 7);
    });
  });

  test('default scan uses only 4h and 1d; research can still cover all', () {
    expect(defaultTimeframes, ['4h', '1d']);
    expect(allTimeframes, ['15m', '1h', '4h', '1d']);
  });
}
