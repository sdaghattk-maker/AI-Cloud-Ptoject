import 'dart:math' as math;
import '../engine/analyzer.dart';
import '../engine/backtest.dart';
import '../ml/ml_filter.dart';
import '../models/signal.dart';

/// خلاصه یک سری (نماد × تایم‌فریم) برای گزارش پژوهشی
class SeriesReport {
  final String symbol, timeframe, strategyName;
  final int candles, firstMs, lastMs;
  final double changePct; // تغییر قیمت از اولین تا آخرین کندل داده
  final AnalyzeResult result;
  final List<OosTrade> oos;
  final List<TradeSample> samples;
  const SeriesReport({
    required this.symbol,
    required this.timeframe,
    required this.strategyName,
    required this.candles,
    required this.firstMs,
    required this.lastMs,
    required this.changePct,
    required this.result,
    required this.oos,
    required this.samples,
  });
}

const _fam = ['pullback', 'breakout', 'reversion'];

/// نام کوتاه انگلیسی خانواده استراتژی (برای گزارش)
String famName(int k) => _fam[k];
const _tfs = ['15m', '1h', '4h', '1d'];

class _Agg {
  final int n;
  final double mean, t, winPct, pf;
  const _Agg(this.n, this.mean, this.t, this.winPct, this.pf);
}

_Agg _agg(List<double> r) {
  final n = r.length;
  if (n == 0) return const _Agg(0, 0, 0, 0, 0);
  var sum = 0.0, gp = 0.0, gl = 0.0;
  var wins = 0;
  for (final x in r) {
    sum += x;
    if (x > 0) {
      gp += x;
      wins++;
    } else if (x < 0) {
      gl -= x;
    }
  }
  final mean = sum / n;
  var v = 0.0;
  for (final x in r) {
    v += (x - mean) * (x - mean);
  }
  final sd = n > 1 ? math.sqrt(v / (n - 1)) : 0.0;
  final t = sd > 0 ? mean / (sd / math.sqrt(n)) : 0.0;
  return _Agg(n, mean, t, wins / n * 100, gl > 0 ? gp / gl : (gp > 0 ? 99.0 : 0.0));
}

String _f(double v, int d) => v.toStringAsFixed(d);
String _sg(double v, int d) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(d)}';
String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

String _aggLine(_Agg a) => 'n=${a.n} avgR=${_sg(a.mean, 3)} win=${_f(a.winPct, 1)}% '
    'PF=${_f(a.pf, 2)} t=${_sg(a.t, 2)}';

/// گزارش متنی فشرده برای تحلیل آماری (قرار است کاربر آن را کپی کند)
String buildResearchReport(List<SeriesReport> rows,
    {List<String> failures = const [], DateTime? now}) {
  final b = StringBuffer();
  final t0 = (now ?? DateTime.now()).toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  b.writeln('CRYPTOSIGNAL RESEARCH REPORT ${t0.year}-${two(t0.month)}-${two(t0.day)} '
      '${two(t0.hour)}:${two(t0.minute)} UTC');
  b.writeln('cost: fee=${_f(fee * 100, 2)}%/side slip=${_f(slippage * 100, 2)}% '
      'maxCostR=$maxCostR | gate: n>=$minOosTrades avgR>$minOosExpectancy '
      'PF>=$minProfitFactor t>=$minOosTStat | walk-forward: train=2000 test=500 | grid=${paramGrid.length}');
  if (rows.isEmpty) {
    b.writeln('NO SERIES ANALYSED');
    for (final f in failures) {
      b.writeln('fail: $f');
    }
    return b.toString();
  }
  final first = rows.map((r) => r.firstMs).reduce(math.min);
  final last = rows.map((r) => r.lastMs).reduce(math.max);
  b.writeln('series analysed: ${rows.length} | failed: ${failures.length} | '
      'data window (all tf): ${_date(first)} .. ${_date(last)}');

  // ---------- [A] هر سری ----------
  b.writeln('\n[A] WALK-FORWARD OOS PER SERIES (strategy chosen on train only)');
  for (final r in rows) {
    final s = r.result.backtest;
    final days = ((r.lastMs - r.firstMs) / 86400000).round();
    b.writeln('${r.symbol.padRight(9)}${r.timeframe.padRight(4)}'
        'bars=${r.candles} days=$days chg=${_sg(r.changePct, 1)}% | '
        '${r.strategyName.isEmpty ? '-' : r.strategyName} | '
        'n=${s.trades} win=${_f(s.winRate, 1)} avgR=${_sg(s.expectancyR, 3)} '
        'PF=${_f(s.profitFactor, 2)} t=${_sg(s.tStat, 2)} dd=${_f(s.maxDdR, 1)}R | '
        '${r.result.edgeOk ? 'PASS' : 'fail'}');
  }

  // ---------- [B] خلاصه گیت ----------
  final passed = rows.where((r) => r.result.edgeOk).length;
  b.writeln('\n[B] GATE SUMMARY');
  b.writeln('passed=$passed/${rows.length} | if there were NO real edge, up to '
      '~${_f(rows.length * 0.067, 1)} series could pass the t test by luck alone '
      '(6.7% one-sided each; other gates lower it)');
  for (final tf in _tfs) {
    final g = rows.where((r) => r.timeframe == tf).toList();
    if (g.isEmpty) continue;
    final a = _agg([for (final r in g) for (final o in r.oos) o.r]);
    b.writeln('  $tf: passed=${g.where((r) => r.result.edgeOk).length}/${g.length} '
        'pooledOOS ${_aggLine(a)}');
  }

  // ---------- [C] مجموع OOS ----------
  final allOos = [for (final r in rows) ...r.oos];
  final pooled = _agg([for (final o in allOos) o.r]);
  b.writeln('\n[C] POOLED OOS (all series; series are correlated, so t is overstated)');
  b.writeln('trades=${pooled.n} avgR=${_sg(pooled.mean, 3)} win=${_f(pooled.winPct, 1)}% '
      'PF=${_f(pooled.pf, 2)} t=${_sg(pooled.t, 2)}');
  b.writeln('by family chosen by walk-forward:');
  for (var k = 0; k < 3; k++) {
    final a = _agg([for (final o in allOos) if (o.strategy == k) o.r]);
    b.writeln('  ${_fam[k].padRight(9)} ${_aggLine(a)}');
  }

  // ---------- [D] خانواده‌ها با پارامتر ثابت (بدون انتخاب) ----------
  final all = [for (final r in rows) ...r.samples];
  b.writeln('\n[D] FIXED-PARAM FAMILIES, NO SELECTION (loose refs: pullback adx>=15; '
      'breakout lb=20; reversion adxMax=30; sl=1.5 ATR; rr2=2; whole history)');
  for (var k = 0; k < 3; k++) {
    final fam = all.where((x) => x.strategy == k).toList();
    final a = _agg([for (final x in fam) x.r]);
    final lg = _agg([for (final x in fam) if (x.side == 1) x.r]);
    final sh = _agg([for (final x in fam) if (x.side == -1) x.r]);
    b.writeln('  ${_fam[k].padRight(9)} ${_aggLine(a)}');
    b.writeln('            long n=${lg.n} avgR=${_sg(lg.mean, 3)} | '
        'short n=${sh.n} avgR=${_sg(sh.mean, 3)}');
    for (final tf in _tfs) {
      final g = [
        for (final r in rows)
          if (r.timeframe == tf)
            for (final x in r.samples)
              if (x.strategy == k) x.r
      ];
      if (g.isEmpty) continue;
      b.writeln('            $tf: ${_aggLine(_agg(g))}');
    }
  }

  // ---------- [E] بافت بازار ----------
  b.writeln('\n[E] MARKET CONTEXT (price change over each timeframe window)');
  for (final tf in _tfs) {
    final g = rows.where((r) => r.timeframe == tf).toList();
    if (g.isEmpty) continue;
    final avg = g.map((r) => r.changePct).reduce((a, c) => a + c) / g.length;
    b.writeln('  $tf: avg change=${_sg(avg, 1)}% over ~'
        '${(g.map((r) => r.lastMs - r.firstMs).reduce((a, c) => a + c) / g.length / 86400000).round()} days');
  }

  if (failures.isNotEmpty) {
    b.writeln('\nFAILURES:');
    for (final f in failures) {
      b.writeln('  $f');
    }
  }
  return b.toString();
}
