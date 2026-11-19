import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptosignal/engine/binance.dart';
import 'package:cryptosignal/models/signal.dart';
import 'package:cryptosignal/paper/paper_store.dart';
import 'package:cryptosignal/paper/paper_trade.dart';

/// هر عنصر [high, low]؛ کندل صفر همان کندل سیگنال است (زمان 0).
Candles mk(List<List<double>> hl) {
  final n = hl.length;
  return Candles(
    [for (var i = 0; i < n; i++) i * 3600000],
    [for (final x in hl) (x[0] + x[1]) / 2],
    [for (final x in hl) x[0]],
    [for (final x in hl) x[1]],
    [for (final x in hl) (x[0] + x[1]) / 2],
    List<double>.filled(n, 1),
  );
}

Signal sig({
  bool long = true,
  double entry = 100,
  double sl = 96,
  double tp1 = 104,
  double tp2 = 112,
  String time = 't',
  double t = 2.5,
  int trades = 30,
  double exp = 0.2,
}) =>
    Signal(
      symbol: 'BTCUSDT',
      timeframe: '1h',
      side: long ? 'LONG' : 'SHORT',
      time: time,
      explanation: '',
      score: 60,
      entry: entry,
      sl: sl,
      tp1: tp1,
      tp2: tp2,
      riskPct: 4,
      backtest: BacktestStats(
          trades: trades,
          winRate: 50,
          expectancyR: exp,
          profitFactor: 1.4,
          maxDdR: 3,
          totalR: 6,
          tStat: t),
      strategy: 'شکست کانال (Donchian)',
    );

PaperTrade tr(Signal s) => PaperTrade.fromSignal(s);

PaperTrade closedTrade(double r, {String strength = 'ضعیف', double bt = 0.2}) {
  final base = PaperTrade.fromSignal(sig(exp: bt, t: strength == 'قوی' ? 3.5 : 1.6,
      trades: strength == 'قوی' ? 60 : 25));
  return base.withSim(PaperSim(closed: true, tp1Hit: true, bars: 5, r: r, outcome: 'tp2'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('simulatePaper (long)', () {
    test('TP1 then TP2 -> positive R about +1.94', () {
      final r = simulatePaper(tr(sig()), mk([
        [101, 99], // کندل سیگنال (نادیده)
        [105, 99], // TP1
        [113, 103], // TP2
      ]));
      expect(r.closed, true);
      expect(r.outcome, 'tp2');
      expect(r.r!, closeTo(1.94, 0.03));
    });

    test('stop loss -> about -1.06R (includes costs)', () {
      final r = simulatePaper(tr(sig()), mk([[101, 99], [101, 95]]));
      expect(r.outcome, 'sl');
      expect(r.r!, closeTo(-1.06, 0.03));
    });

    test('SL and TP1 in the same candle -> stop first (conservative)', () {
      final r = simulatePaper(tr(sig()), mk([[101, 99], [105, 95]]));
      expect(r.outcome, 'sl');
      expect(r.tp1Hit, false);
    });

    test('TP1 then break-even stop -> small positive R', () {
      final r = simulatePaper(tr(sig()), mk([[101, 99], [105, 99.5], [101, 99]]));
      expect(r.outcome, 'tp1_be');
      expect(r.r!, closeTo(0.446, 0.03));
    });

    test('price still between levels -> stays open', () {
      final r = simulatePaper(tr(sig()), mk([[101, 99], [102, 98]]));
      expect(r.closed, false);
      expect(r.tp1Hit, false);
      expect(r.r, isNull);
    });

    test('TP1 reached but not finished -> open with tp1Hit', () {
      final r = simulatePaper(tr(sig()), mk([[101, 99], [105, 99.5]]));
      expect(r.closed, false);
      expect(r.tp1Hit, true);
    });

    test('timeout after maxHold bars closes near entry', () {
      final r = simulatePaper(
          tr(sig()), mk([[101, 99], ...List.generate(100, (_) => [101.0, 99.0])]));
      expect(r.outcome, 'timeout');
      expect(r.r!, closeTo(-0.06, 0.03));
    });

    test('the signal candle itself is ignored', () {
      final r = simulatePaper(tr(sig()), mk([[200, 1], [102, 98]]));
      expect(r.closed, false);
    });
  });

  test('simulatePaper (short) TP1 then TP2 -> about +1.94', () {
    final s = sig(long: false, entry: 100, sl: 104, tp1: 96, tp2: 88);
    final r = simulatePaper(tr(s), mk([[101, 99], [101, 95], [97, 87]]));
    expect(r.outcome, 'tp2');
    expect(r.r!, closeTo(1.94, 0.03));
  });

  test('fromSignal builds a stable id and JSON round-trips', () {
    final t = tr(sig(time: '2026-11-17T10:00:00.000Z'));
    expect(t.id, startsWith('BTCUSDT|1h|'));
    expect(t.signalTimeMs, DateTime.parse('2026-11-17T10:00:00.000Z').millisecondsSinceEpoch);
    final closed = t.withSim(const PaperSim(
        closed: true, tp1Hit: true, bars: 7, r: 1.5, outcome: 'tp2', exitPrice: 112, closedAtMs: 99));
    final back = PaperTrade.fromJson(closed.toJson());
    expect(back.id, closed.id);
    expect(back.isClosed, true);
    expect(back.resultR, 1.5);
    expect(back.outcome, 'tp2');
    expect(back.strength, closed.strength);
  });

  group('summary and live verdict', () {
    test('counts, stats and strength groups', () {
      final list = [
        closedTrade(2.0, strength: 'قوی'),
        closedTrade(-1.0, strength: 'ضعیف'),
        closedTrade(1.0, strength: 'ضعیف'),
        tr(sig(time: '2026-11-17T10:00:00.000Z')), // هنوز باز
      ];
      final s = summarize(list);
      expect(s.total, 4);
      expect(s.closed, 3);
      expect(s.open, 1);
      expect(s.stats.trades, 3);
      expect(s.stats.expectancyR, closeTo(0.667, 0.01));
      expect(s.byStrength['قوی']!.n, 1);
      expect(s.byStrength['ضعیف']!.n, 2);
      expect(s.byStrength['ضعیف']!.avgR, closeTo(0, 1e-9));
      expect(s.byStrength.containsKey('متوسط'), false);
    });

    test('too few closed trades -> too early to judge', () {
      expect(liveVerdict(summarize([closedTrade(1.0)])), contains('زود'));
    });

    test('30 losing trades -> warns not to use real money', () {
      final s = summarize([for (var i = 0; i < 30; i++) closedTrade(-0.5)]);
      expect(liveVerdict(s), contains('سودآور نبوده'));
    });

    test('consistently positive -> statistically significant', () {
      final s = summarize(
          [for (var i = 0; i < 30; i++) closedTrade(i.isEven ? 1.2 : 0.8)]);
      expect(liveVerdict(s), contains('مثبت و از نظر آماری معنادار'));
    });

    test('positive but noisy -> not yet significant', () {
      final s = summarize(
          [for (var i = 0; i < 30; i++) closedTrade(i.isEven ? 1.0 : -0.8)]);
      expect(liveVerdict(s), contains('هنوز از نظر آماری معنادار نیست'));
    });
  });

  test('outcome labels and timeframe lengths', () {
    expect(outcomeLabel('sl'), isNotEmpty);
    expect(outcomeLabel('unknown'), '');
    expect(tfMs('15m'), 900000);
    expect(tfMs('4h'), 4 * 3600000);
    expect(tfMs('1d'), 86400000);
  });

  test('PaperStore dedupes the same signal and can clear', () async {
    SharedPreferences.setMockInitialValues({});
    final s = sig(time: '2026-11-17T10:00:00.000Z');
    expect(await PaperStore.record(s), true);
    expect(await PaperStore.record(s), false);
    expect((await PaperStore.load()).length, 1);
    final other = sig(time: '2026-11-17T11:00:00.000Z');
    expect(await PaperStore.record(other), true);
    expect((await PaperStore.load()).length, 2);
    await PaperStore.clear();
    expect(await PaperStore.load(), isEmpty);
  });
}
