import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptosignal/engine/analyzer.dart';
import 'package:cryptosignal/engine/binance.dart';
import 'package:cryptosignal/ml/ml_filter.dart';
import 'package:cryptosignal/models/signal.dart';
import 'package:cryptosignal/research/report.dart';

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

const _stats = BacktestStats(
    trades: 20,
    winRate: 50,
    expectancyR: 0.0,
    profitFactor: 1.0,
    maxDdR: 2,
    totalR: 0,
    tStat: 0);

SeriesReport row(String sym, String tf, String strat, bool edge, List<OosTrade> oos,
        List<TradeSample> samples) =>
    SeriesReport(
      symbol: sym,
      timeframe: tf,
      strategyName: strat,
      candles: 5000,
      firstMs: 1700000000000,
      lastMs: 1700000000000 + 30 * 86400000,
      changePct: 12.5,
      result: AnalyzeResult(
          symbol: sym,
          timeframe: tf,
          candles: 5000,
          edgeOk: edge,
          backtest: _stats,
          signal: null),
      oos: oos,
      samples: samples,
    );

TradeSample smp(double r, int strat, int side) => TradeSample(
    timeMs: 0, endMs: 0, x: const [0.0], r: r, side: side, strategy: strat);

void main() {
  final rows = [
    row('BTCUSDT', '1h', 'pullback', false, [
      for (var i = 0; i < 10; i++) const OosTrade(1.0, 0),
      for (var i = 0; i < 10; i++) const OosTrade(-1.0, 0),
    ], [
      for (var i = 0; i < 5; i++) smp(1.0, 0, 1),
      for (var i = 0; i < 5; i++) smp(-1.0, 0, -1),
    ]),
    row('ETHUSDT', '4h', 'breakout', true, [
      for (var i = 0; i < 20; i++) const OosTrade(0.5, 1),
    ], [
      for (var i = 0; i < 10; i++) smp(0.5, 1, 1),
    ]),
  ];

  test('report has all sections and per-series rows', () {
    final r = buildResearchReport(rows, now: DateTime.utc(2026, 11, 19, 10, 30));
    expect(r, contains('CRYPTOSIGNAL RESEARCH REPORT 2026-11-19 10:30 UTC'));
    for (final sec in ['[A]', '[B]', '[C]', '[D]', '[E]']) {
      expect(r, contains(sec));
    }
    expect(r, contains('BTCUSDT'));
    expect(r, contains('ETHUSDT'));
    expect(r, contains('series analysed: 2'));
    expect(r, contains('PASS'));
    expect(r, contains('fail'));
    expect(r, contains('chg=+12.5%'));
  });

  test('gate summary counts passes and mentions the chance expectation', () {
    final r = buildResearchReport(rows);
    expect(r, contains('passed=1/2'));
    expect(r, contains('1h: passed=0/1'));
    expect(r, contains('4h: passed=1/1'));
    expect(r, contains('by luck alone'));
  });

  test('pooled OOS numbers are exact', () {
    final r = buildResearchReport(rows);
    expect(r, contains('trades=40'));
    expect(r, contains('avgR=+0.250'));
    expect(r, contains('n=20 avgR=+0.000')); // pullback
    expect(r, contains('n=20 avgR=+0.500')); // breakout
    expect(r, contains('n=0 avgR=+0.000')); // reversion (no trades)
  });

  test('fixed-parameter families are split by direction', () {
    final r = buildResearchReport(rows);
    expect(r, contains('long n=5 avgR=+1.000'));
    expect(r, contains('short n=5 avgR=-1.000'));
    expect(r, contains('long n=10 avgR=+0.500'));
  });

  test('empty input and failures are reported without crashing', () {
    final r = buildResearchReport(const [], failures: ['BTCUSDT 1h: no network']);
    expect(r, contains('NO SERIES ANALYSED'));
    expect(r, contains('no network'));
    final withFail = buildResearchReport(rows, failures: ['XRPUSDT 1d: timeout']);
    expect(withFail, contains('FAILURES'));
    expect(withFail, contains('XRPUSDT 1d: timeout'));
  });

  test('family names are stable', () {
    expect([for (var k = 0; k < 3; k++) famName(k)], ['pullback', 'breakout', 'reversion']);
  });

  test('a real analysis on synthetic data feeds a clean report', () {
    final c = synthetic(5000, 7);
    final s = analyzeSeries('TESTUSDT', '1h', c);
    // معاملات خارج از نمونه ثبت‌شده باید دقیقاً همان‌هایی باشند که در آمار آمده
    expect(s.oos.length, s.result.backtest.trades);
    expect(s.samples.every((x) => (x.side == 1 || x.side == -1) && x.strategy >= 0 && x.strategy <= 2), true);
    final p = s.params;
    final rep = buildResearchReport([
      SeriesReport(
        symbol: 'TESTUSDT',
        timeframe: '1h',
        strategyName: p == null ? '' : famName(p.strategy),
        candles: c.length,
        firstMs: c.times.first,
        lastMs: c.times.last,
        changePct: (c.close.last / c.close.first - 1) * 100,
        result: s.result,
        oos: s.oos,
        samples: s.samples,
      )
    ]);
    expect(rep, contains('TESTUSDT'));
    expect(rep, contains('[D]'));
    expect(rep, isNot(contains('NaN')));
    expect(rep, isNot(contains('Infinity')));
  });

  test('raw-edge section separates gross from net and shows costs and stops', () {
    final rows2 = [
      row('BTCUSDT', '4h', 'breakout', false, [
        for (var i = 0; i < 10; i++) const OosTrade(-0.1, 1, 0.2, 1.0),
      ], [
        for (var i = 0; i < 10; i++)
          TradeSample(
              timeMs: 0,
              endMs: 0,
              x: const [0.0],
              r: -0.1,
              side: 1,
              strategy: 1,
              costR: 0.2,
              riskPct: 1.0),
      ]),
    ];
    final r = buildResearchReport(rows2);
    expect(r, contains('[F]'));
    expect(r, contains('net=-0.100'));
    expect(r, contains('gross=+0.100'));
    expect(r, contains('cost=0.200R'));
    expect(r, contains('stop=1.00%'));
    expect(r, contains('BTCUSDT only:'));
    expect(r, isNot(contains('ETHUSDT only:')));
    expect(r, contains('reading: gross~0'));
  });

  test('raw edge has an empty-safe form and old data without costs stays sane', () {
    final r = buildResearchReport(rows); // نمونه‌های بدون هزینه (۰)
    expect(r, contains('[F]'));
    expect(r, contains('n=0')); // خانواده بدون معامله
    expect(r, contains('cost=0.000R')); // هزینه ثبت‌نشده = ۰، خام = خالص
    expect(r, isNot(contains('NaN')));
  });
}
