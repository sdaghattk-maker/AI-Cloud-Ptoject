import 'dart:math' as math;
import '../engine/backtest.dart';
import '../engine/binance.dart';
import '../engine/decision.dart';
import '../engine/indicators.dart';
import '../engine/strategy.dart';

/// اعتبارسنجی متمرکز «شکست کانال روی روزانه» با پارامتر ثابت (بدون انتخاب/بهینه‌سازی)
const dailyLookbacks = [20, 50];
const dailySls = [1.2, 1.5, 2.0];
const dailyRrs = [2.0, 3.0];

String dailyKey(int lb, double sl, double rr) => 'lb$lb/sl$sl/rr$rr';
const dailyRefKey = 'lb20/sl1.5/rr2.0';

class DailyTrade {
  final String symbol;
  final int entryMs, exitMs, side;
  final double r, cost, riskPct; // r خالص؛ خام = r + cost
  const DailyTrade({
    required this.symbol,
    required this.entryMs,
    required this.exitMs,
    required this.side,
    required this.r,
    required this.cost,
    required this.riskPct,
  });
}

class DailySeries {
  final String symbol;
  final int candles, firstMs, lastMs;
  final double changePct;
  final Map<String, List<DailyTrade>> trades; // به تفکیک پیکربندی
  const DailySeries({
    required this.symbol,
    required this.candles,
    required this.firstMs,
    required this.lastMs,
    required this.changePct,
    required this.trades,
  });
}

DailySeries analyzeDaily(String symbol, Candles c) {
  final n = c.length;
  final d = computeIndicators(c);
  final trades = <String, List<DailyTrade>>{};
  for (final lb in dailyLookbacks) {
    final sig = buildBreakout(d, lb);
    for (final sl in dailySls) {
      for (final rr in dailyRrs) {
        final p = Params(0, sl, rr, strategy: 1, param: lb.toDouble());
        final tr = n > 250 ? runBacktest(d, sig, p, 200, n) : <Trade>[];
        trades[dailyKey(lb, sl, rr)] = [
          for (final t in tr)
            DailyTrade(
              symbol: symbol,
              entryMs: c.times[t.bar],
              exitMs: c.times[math.min(t.bar + t.bars, n - 1)],
              side: t.side,
              r: t.r,
              cost: t.costR,
              riskPct: t.riskPct,
            )
        ];
      }
    }
  }
  return DailySeries(
    symbol: symbol,
    candles: n,
    firstMs: n > 0 ? c.times.first : 0,
    lastMs: n > 0 ? c.times.last : 0,
    changePct: n > 1 ? (c.close.last / c.close.first - 1) * 100 : 0,
    trades: trades,
  );
}

// ---------------------------------------------------------------- آمار

class _Agg {
  final int n;
  final double mean, t, win;
  const _Agg(this.n, this.mean, this.t, this.win);
}

_Agg _agg(Iterable<double> values) {
  final r = values.toList();
  final n = r.length;
  if (n == 0) return const _Agg(0, 0, 0, 0);
  var sum = 0.0;
  var wins = 0;
  for (final x in r) {
    sum += x;
    if (x > 0) wins++;
  }
  final mean = sum / n;
  var v = 0.0;
  for (final x in r) {
    v += (x - mean) * (x - mean);
  }
  final sd = n > 1 ? math.sqrt(v / (n - 1)) : 0.0;
  return _Agg(n, mean, sd > 0 ? mean / (sd / math.sqrt(n)) : 0.0, wins / n * 100);
}

String _f(double v, int d) => v.toStringAsFixed(d);
String _sg(double v, int d) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(d)}';

String _line(List<DailyTrade> t) {
  if (t.isEmpty) return 'n=0';
  final net = _agg(t.map((x) => x.r));
  final gross = _agg(t.map((x) => x.r + x.cost));
  final cost = t.map((x) => x.cost).reduce((a, c) => a + c) / t.length;
  final stop = t.map((x) => x.riskPct).reduce((a, c) => a + c) / t.length;
  return 'n=${net.n} net=${_sg(net.mean, 3)} (t=${_sg(net.t, 2)}) '
      'gross=${_sg(gross.mean, 3)} win=${_f(net.win, 1)}% cost=${_f(cost, 3)}R stop=${_f(stop, 2)}%';
}

String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

List<DailyTrade> _ref(List<DailySeries> rows) =>
    [for (final r in rows) ...(r.trades[dailyRefKey] ?? const <DailyTrade>[])];

final int _y2020 = DateTime.utc(2020).millisecondsSinceEpoch;
const double _yearMs = 365.25 * 86400000;

// ---------------------------------------------------------------- پرتفوی

class PortfolioResult {
  final int taken, skipped;
  final double finalMult, maxDdPct, years, cagrPct;
  const PortfolioResult(
      this.taken, this.skipped, this.finalMult, this.maxDdPct, this.years, this.cagrPct);
}

class _Open {
  final int exitMs;
  final double riskAmt, r;
  const _Open(this.exitMs, this.riskAmt, this.r);
}

/// شبیه‌سازی پرتفوی: هر معامله [risk] از سرمایه محقق‌شده را ریسک می‌کند؛ بیش از [cap] پوزیشن هم‌زمان
/// ممکن نیست (معاملات اضافه ردّ می‌شوند). افت سرمایه روی سرمایه محقق‌شده حساب می‌شود.
PortfolioResult simulatePortfolio(List<DailyTrade> all,
    {required int cap, double risk = 0.01}) {
  if (all.isEmpty) return const PortfolioResult(0, 0, 1, 0, 0, 0);
  final trades = [...all]..sort((a, b) => a.entryMs.compareTo(b.entryMs));
  var equity = 1.0, peak = 1.0, maxDd = 0.0;
  var taken = 0, skipped = 0;
  var maxExit = 0;
  final open = <_Open>[];

  void realize(int t) {
    open.sort((a, b) => a.exitMs.compareTo(b.exitMs));
    while (open.isNotEmpty && open.first.exitMs <= t) {
      final o = open.removeAt(0);
      equity += o.riskAmt * o.r;
      if (equity > peak) peak = equity;
      final dd = (peak - equity) / peak;
      if (dd > maxDd) maxDd = dd;
    }
  }

  for (final t in trades) {
    realize(t.entryMs);
    if (open.length < cap) {
      open.add(_Open(t.exitMs, equity * risk, t.r));
      taken++;
      maxExit = math.max(maxExit, t.exitMs);
    } else {
      skipped++;
    }
  }
  realize(1 << 62);

  final years = math.max(1e-9, (maxExit - trades.first.entryMs) / _yearMs);
  final cagr = equity > 0 ? (math.pow(equity, 1 / years) - 1) * 100 : -100.0;
  return PortfolioResult(taken, skipped, equity, maxDd * 100, years, cagr);
}

// ---------------------------------------------------------------- شرط‌ها

/// هفت شرط از پیش تعیین‌شده؛ همه با هم برقرار بودن «اثبات» نیست، ولی یک رد حتی یکی از آن‌ها
/// یعنی نتیجه شکننده است.
List<CheckItem> dailyChecks(List<DailySeries> rows) {
  final ref = _ref(rows);
  final all = _agg(ref.map((t) => t.r));

  final sorted = [...ref]..sort((a, b) => a.entryMs.compareTo(b.entryMs));
  final mid = sorted.isEmpty ? 0 : sorted[sorted.length ~/ 2].entryMs;
  final h1 = _agg(sorted.where((t) => t.entryMs < mid).map((t) => t.r));
  final h2 = _agg(sorted.where((t) => t.entryMs >= mid).map((t) => t.r));
  final post = _agg(ref.where((t) => t.entryMs >= _y2020).map((t) => t.r));

  // حذف یک‌به‌یک نمادها
  var looOk = rows.length > 1;
  var looMin = double.infinity;
  for (final s in rows) {
    final a = _agg(ref.where((t) => t.symbol != s.symbol).map((t) => t.r));
    looMin = math.min(looMin, a.mean);
    if (!(a.n > 0 && a.mean > 0)) looOk = false;
  }

  // BTC و ETH
  String btcEth = '';
  var btcEthOk = true;
  for (final sym in const ['BTCUSDT', 'ETHUSDT']) {
    final a = _agg(ref.where((t) => t.symbol == sym).map((t) => t.r));
    btcEth += '$sym ${_sg(a.mean, 2)} (n=${a.n})  ';
    if (!(a.n >= 15 && a.mean > 0)) btcEthOk = false;
  }

  // استحکام پارامتر
  var posCfg = 0, totCfg = 0;
  for (final lb in dailyLookbacks) {
    for (final sl in dailySls) {
      for (final rr in dailyRrs) {
        final tr = [
          for (final r in rows) ...(r.trades[dailyKey(lb, sl, rr)] ?? const <DailyTrade>[])
        ];
        if (tr.isEmpty) continue;
        totCfg++;
        if (_agg(tr.map((t) => t.r)).mean > 0) posCfg++;
      }
    }
  }

  final pf = simulatePortfolio(ref, cap: 3);

  return [
    CheckItem('کل تاریخچه: میانگین خالص مثبت و t ≥ 2', all.n >= 100 && all.mean > 0 && all.t >= 2,
        'n=${all.n} ${_sg(all.mean, 3)}R t=${_sg(all.t, 2)}'),
    CheckItem('هر دو نیمه زمانی مثبت', h1.n >= 30 && h2.n >= 30 && h1.mean > 0 && h2.mean > 0,
        'نیمه اول ${_sg(h1.mean, 3)} · دوم ${_sg(h2.mean, 3)}'),
    CheckItem('از ۲۰۲۰ به بعد مثبت', post.n >= 50 && post.mean > 0,
        'n=${post.n} ${_sg(post.mean, 3)}R'),
    CheckItem('با حذف هر نماد، هنوز مثبت', looOk,
        looMin.isFinite ? 'کمترین ${_sg(looMin, 3)}R' : '—'),
    CheckItem('BTC و ETH هرکدام مثبت', btcEthOk, btcEth.trim()),
    CheckItem('استحکام پارامتر: حداقل ۹ از ۱۲ ترکیب مثبت', totCfg >= 12 && posCfg >= 9,
        '$posCfg از $totCfg'),
    CheckItem('پرتفوی (سقف ۳ پوزیشن، ریسک ۱٪): بازده مثبت', pf.taken > 0 && pf.finalMult > 1,
        '${_sg(pf.cagrPct, 1)}٪ سالانه · افت ${_f(pf.maxDdPct, 1)}٪'),
  ];
}

// ---------------------------------------------------------------- گزارش

String buildDailyReport(List<DailySeries> rows,
    {List<String> failures = const [], DateTime? now}) {
  final b = StringBuffer();
  final t0 = (now ?? DateTime.now()).toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  b.writeln('CRYPTOSIGNAL DAILY BREAKOUT VALIDATION ${t0.year}-${two(t0.month)}-${two(t0.day)} '
      '${two(t0.hour)}:${two(t0.minute)} UTC');
  if (rows.isEmpty) {
    b.writeln('NO SERIES ANALYSED');
    for (final f in failures) {
      b.writeln('fail: $f');
    }
    return b.toString();
  }
  final ref = _ref(rows);

  b.writeln('\n[1] SCOPE');
  b.writeln('1d donchian breakout (EMA200 trend filter, ADX>=18, vol>=1.0x), FIXED params, no selection. '
      'reference: lookback=20, stop=1.5 ATR, rr2=2 | cost: fee=${_f(fee * 100, 2)}%/side '
      'slip=${_f(slippage * 100, 2)}% maxCostR=$maxCostR');
  b.writeln('symbols=${rows.length} (current top coins => SURVIVORSHIP BIAS: dead coins are absent) | '
      'data ${_date(rows.map((r) => r.firstMs).reduce(math.min))} .. '
      '${_date(rows.map((r) => r.lastMs).reduce(math.max))} | failed=${failures.length}');

  b.writeln('\n[2] REFERENCE CONFIG, POOLED');
  b.writeln('all    ${_line(ref)}');
  b.writeln('long   ${_line(ref.where((t) => t.side == 1).toList())}');
  b.writeln('short  ${_line(ref.where((t) => t.side == -1).toList())}');

  b.writeln('\n[3] PER SYMBOL (reference config)');
  for (final r in rows) {
    final years = ((r.lastMs - r.firstMs) / _yearMs);
    b.writeln('${r.symbol.padRight(9)}bars=${r.candles} yrs=${_f(years, 1)} '
        'chg=${_sg(r.changePct, 0)}% | ${_line(r.trades[dailyRefKey] ?? const [])}');
  }

  b.writeln('\n[4] STABILITY (reference config)');
  final sorted = [...ref]..sort((a, c) => a.entryMs.compareTo(c.entryMs));
  if (sorted.isNotEmpty) {
    final mid = sorted[sorted.length ~/ 2].entryMs;
    b.writeln('halves split at ${_date(mid)}:');
    b.writeln('  first  half ${_line(sorted.where((t) => t.entryMs < mid).toList())}');
    b.writeln('  second half ${_line(sorted.where((t) => t.entryMs >= mid).toList())}');
    b.writeln('before/after 2020:');
    b.writeln('  before ${_line(sorted.where((t) => t.entryMs < _y2020).toList())}');
    b.writeln('  since  ${_line(sorted.where((t) => t.entryMs >= _y2020).toList())}');
    b.writeln('by year:');
    final years = {for (final t in sorted) DateTime.fromMillisecondsSinceEpoch(t.entryMs, isUtc: true).year}
        .toList()
      ..sort();
    for (final y in years) {
      final g = sorted
          .where((t) => DateTime.fromMillisecondsSinceEpoch(t.entryMs, isUtc: true).year == y)
          .toList();
      final a = _agg(g.map((t) => t.r));
      b.writeln('  $y n=${a.n} net=${_sg(a.mean, 3)} (t=${_sg(a.t, 2)})');
    }
    b.writeln('leave-one-symbol-out (pooled net avgR without that symbol):');
    for (final s in rows) {
      final a = _agg(ref.where((t) => t.symbol != s.symbol).map((t) => t.r));
      b.writeln('  without ${s.symbol.padRight(9)} n=${a.n} net=${_sg(a.mean, 3)} (t=${_sg(a.t, 2)})');
    }
  }

  b.writeln('\n[5] PARAMETER ROBUSTNESS (pooled, all symbols)');
  var pos = 0, tot = 0;
  for (final lb in dailyLookbacks) {
    for (final sl in dailySls) {
      for (final rr in dailyRrs) {
        final tr = [
          for (final r in rows) ...(r.trades[dailyKey(lb, sl, rr)] ?? const <DailyTrade>[])
        ];
        final a = _agg(tr.map((t) => t.r));
        tot++;
        if (a.n > 0 && a.mean > 0) pos++;
        b.writeln('  lb=$lb sl=$sl rr=$rr  n=${a.n} net=${_sg(a.mean, 3)} (t=${_sg(a.t, 2)})');
      }
    }
  }
  b.writeln('  positive configs: $pos/$tot');

  b.writeln('\n[6] PORTFOLIO SIMULATION (risk 1% of realised equity per trade; realised-equity drawdown, '
      'understates true drawdown)');
  for (final cap in const [1, 3, 5, 100]) {
    final p = simulatePortfolio(ref, cap: cap);
    b.writeln('  cap=${cap.toString().padRight(3)} taken=${p.taken} skipped=${p.skipped} '
        'final=x${_f(p.finalMult, 2)} cagr=${_sg(p.cagrPct, 1)}% maxDD=${_f(p.maxDdPct, 1)}% '
        'years=${_f(p.years, 1)}');
  }
  final pl = simulatePortfolio(ref.where((t) => t.side == 1).toList(), cap: 3);
  b.writeln('  long-only cap=3 taken=${pl.taken} skipped=${pl.skipped} '
      'final=x${_f(pl.finalMult, 2)} cagr=${_sg(pl.cagrPct, 1)}% maxDD=${_f(pl.maxDdPct, 1)}%');

  b.writeln('\n[7] CHECKS (pre-registered; all passing is NOT proof, any failing means fragile)');
  for (final c in dailyChecks(rows)) {
    b.writeln('  ${c.ok == true ? 'PASS' : 'fail'}  ${c.label} | ${c.detail}');
  }

  if (failures.isNotEmpty) {
    b.writeln('\nFAILURES:');
    for (final f in failures) {
      b.writeln('  $f');
    }
  }
  return b.toString();
}
