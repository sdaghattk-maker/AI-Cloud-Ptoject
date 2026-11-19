import '../engine/backtest.dart';
import '../engine/binance.dart';
import '../engine/decision.dart';
import '../models/signal.dart';

int tfMs(String tf) {
  switch (tf) {
    case '15m':
      return 900000;
    case '4h':
      return 14400000;
    case '1d':
      return 86400000;
    default:
      return 3600000;
  }
}

/// نتیجه شبیه‌سازی یک معامله آزمایشی روی کندل‌های بسته‌شده بعد از سیگنال
class PaperSim {
  final bool closed, tp1Hit;
  final int bars;
  final double? r, exitPrice;
  final String outcome; // tp2 | sl | tp1_be | timeout | ''
  final int? closedAtMs;
  const PaperSim({
    required this.closed,
    required this.tp1Hit,
    required this.bars,
    this.r,
    this.exitPrice,
    this.outcome = '',
    this.closedAtMs,
  });
}

class PaperTrade {
  final String id, symbol, timeframe, strategy, strength, status, outcome;
  final int side, signalTimeMs, createdAtMs, barsHeld;
  final double entry, sl, tp1, tp2, btExpectancyR, btTStat;
  final bool mlApproved, tp1Hit;
  final double? resultR, exitPrice;
  final int? closedAtMs;

  const PaperTrade({
    required this.id,
    required this.symbol,
    required this.timeframe,
    required this.strategy,
    required this.strength,
    required this.status,
    required this.outcome,
    required this.side,
    required this.signalTimeMs,
    required this.createdAtMs,
    required this.barsHeld,
    required this.entry,
    required this.sl,
    required this.tp1,
    required this.tp2,
    required this.btExpectancyR,
    required this.btTStat,
    required this.mlApproved,
    required this.tp1Hit,
    this.resultR,
    this.exitPrice,
    this.closedAtMs,
  });

  bool get isClosed => status == 'closed' && resultR != null;
  bool get isLong => side == 1;

  /// ثبت سیگنال در لحظه صدور (قبل از دانستن نتیجه)
  factory PaperTrade.fromSignal(Signal s, {int? nowMs}) {
    final t = DateTime.tryParse(s.time)?.millisecondsSinceEpoch ?? 0;
    return PaperTrade(
      id: '${s.symbol}|${s.timeframe}|$t',
      symbol: s.symbol,
      timeframe: s.timeframe,
      strategy: s.strategy,
      strength: strengthOf(s.backtest, mlApproved: s.mlApproved),
      status: 'open',
      outcome: '',
      side: s.isLong ? 1 : -1,
      signalTimeMs: t,
      createdAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
      barsHeld: 0,
      entry: s.entry,
      sl: s.sl,
      tp1: s.tp1,
      tp2: s.tp2,
      btExpectancyR: s.backtest.expectancyR,
      btTStat: s.backtest.tStat,
      mlApproved: s.mlApproved,
      tp1Hit: false,
    );
  }

  PaperTrade withSim(PaperSim sim) => PaperTrade(
        id: id,
        symbol: symbol,
        timeframe: timeframe,
        strategy: strategy,
        strength: strength,
        status: sim.closed ? 'closed' : 'open',
        outcome: sim.outcome,
        side: side,
        signalTimeMs: signalTimeMs,
        createdAtMs: createdAtMs,
        barsHeld: sim.bars,
        entry: entry,
        sl: sl,
        tp1: tp1,
        tp2: tp2,
        btExpectancyR: btExpectancyR,
        btTStat: btTStat,
        mlApproved: mlApproved,
        tp1Hit: sim.tp1Hit,
        resultR: sim.r,
        exitPrice: sim.exitPrice,
        closedAtMs: sim.closedAtMs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'symbol': symbol,
        'timeframe': timeframe,
        'strategy': strategy,
        'strength': strength,
        'status': status,
        'outcome': outcome,
        'side': side,
        'signalTimeMs': signalTimeMs,
        'createdAtMs': createdAtMs,
        'barsHeld': barsHeld,
        'entry': entry,
        'sl': sl,
        'tp1': tp1,
        'tp2': tp2,
        'btExpectancyR': btExpectancyR,
        'btTStat': btTStat,
        'mlApproved': mlApproved,
        'tp1Hit': tp1Hit,
        'resultR': resultR,
        'exitPrice': exitPrice,
        'closedAtMs': closedAtMs,
      };

  factory PaperTrade.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => (v as num).toDouble();
    return PaperTrade(
      id: j['id'] as String,
      symbol: j['symbol'] as String,
      timeframe: j['timeframe'] as String,
      strategy: (j['strategy'] ?? '') as String,
      strength: (j['strength'] ?? '') as String,
      status: (j['status'] ?? 'open') as String,
      outcome: (j['outcome'] ?? '') as String,
      side: (j['side'] as num).toInt(),
      signalTimeMs: (j['signalTimeMs'] as num).toInt(),
      createdAtMs: (j['createdAtMs'] as num).toInt(),
      barsHeld: ((j['barsHeld'] ?? 0) as num).toInt(),
      entry: d(j['entry']),
      sl: d(j['sl']),
      tp1: d(j['tp1']),
      tp2: d(j['tp2']),
      btExpectancyR: d(j['btExpectancyR'] ?? 0),
      btTStat: d(j['btTStat'] ?? 0),
      mlApproved: (j['mlApproved'] ?? false) as bool,
      tp1Hit: (j['tp1Hit'] ?? false) as bool,
      resultR: j['resultR'] == null ? null : d(j['resultR']),
      exitPrice: j['exitPrice'] == null ? null : d(j['exitPrice']),
      closedAtMs: j['closedAtMs'] == null ? null : (j['closedAtMs'] as num).toInt(),
    );
  }
}

/// شبیه‌سازی با همان قواعد بک‌تست: فقط کندل‌های بسته‌شده «بعد از» کندل سیگنال؛
/// اگر SL و TP در یک کندل بخورند اول SL؛ نیمی در TP1 و انتقال SL به ورود؛ باقی تا TP2؛
/// کارمزد و لغزش اعمال می‌شود؛ حداکثر [maxHold] کندل نگهداری.
PaperSim simulatePaper(PaperTrade t, Candles c) {
  final s = t.side;
  final risk = (t.entry - t.sl).abs();
  if (risk <= 0) {
    return const PaperSim(closed: true, tp1Hit: false, bars: 0, r: 0, outcome: 'sl');
  }
  final e = t.entry * (1 + slippage * s);
  var rem = 1.0, pnl = 0.0;
  var done = false, bars = 0;
  var slCur = t.sl;
  String outcome = '';
  double? exit;
  int? closedAt;

  for (var i = 0; i < c.length; i++) {
    if (c.times[i] <= t.signalTimeMs) continue;
    bars++;
    final hi = c.high[i], lo = c.low[i];
    final hitSl = s == 1 ? lo <= slCur : hi >= slCur;
    if (hitSl) {
      pnl += rem * s * (slCur - e);
      rem = 0;
      outcome = done ? 'tp1_be' : 'sl';
      exit = slCur;
      closedAt = c.times[i];
      break;
    }
    if (!done && (s == 1 ? hi >= t.tp1 : lo <= t.tp1)) {
      pnl += 0.5 * s * (t.tp1 - e);
      rem = 0.5;
      done = true;
      slCur = e;
    }
    if (done && (s == 1 ? hi >= t.tp2 : lo <= t.tp2)) {
      pnl += rem * s * (t.tp2 - e);
      rem = 0;
      outcome = 'tp2';
      exit = t.tp2;
      closedAt = c.times[i];
      break;
    }
    if (bars >= maxHold) {
      pnl += rem * s * (c.close[i] - e);
      rem = 0;
      outcome = 'timeout';
      exit = c.close[i];
      closedAt = c.times[i];
      break;
    }
  }

  if (rem > 0) {
    return PaperSim(closed: false, tp1Hit: done, bars: bars);
  }
  final fees = fee * 2 * e;
  return PaperSim(
    closed: true,
    tp1Hit: done,
    bars: bars,
    r: (pnl - fees) / risk,
    exitPrice: exit,
    outcome: outcome,
    closedAtMs: closedAt,
  );
}

class GroupStat {
  final int n;
  final double avgR;
  const GroupStat(this.n, this.avgR);
}

class PaperSummary {
  final int total, open, closed;
  final BacktestStats stats; // فقط معاملات بسته‌شده
  final double avgBacktestR; // میانگین انتظار بک‌تست هنگام صدور (معاملات بسته‌شده)
  final Map<String, GroupStat> byStrength;
  const PaperSummary({
    required this.total,
    required this.open,
    required this.closed,
    required this.stats,
    required this.avgBacktestR,
    required this.byStrength,
  });
}

PaperSummary summarize(List<PaperTrade> list) {
  final closed = list.where((t) => t.isClosed).toList();
  final stats =
      statsOf([for (final t in closed) Trade(t.resultR!, 0, t.side, t.barsHeld)]);
  final bt = closed.isEmpty
      ? 0.0
      : closed.map((t) => t.btExpectancyR).reduce((a, b) => a + b) / closed.length;
  final groups = <String, GroupStat>{};
  for (final k in const ['قوی', 'متوسط', 'ضعیف']) {
    final g = closed.where((t) => t.strength == k).toList();
    if (g.isNotEmpty) {
      groups[k] = GroupStat(
          g.length, g.map((t) => t.resultR!).reduce((a, b) => a + b) / g.length);
    }
  }
  return PaperSummary(
    total: list.length,
    open: list.length - closed.length,
    closed: closed.length,
    stats: stats,
    avgBacktestR: bt,
    byStrength: groups,
  );
}

const paperMinTrades = 30;

/// قضاوت صادقانه درباره نتیجه زنده
String liveVerdict(PaperSummary s) {
  if (s.closed < paperMinTrades) {
    return 'هنوز زود است؛ برای قضاوت حداقل $paperMinTrades معامله بسته‌شده لازم است '
        '(الان ${s.closed}).';
  }
  if (s.stats.expectancyR <= 0) {
    return 'تا اینجا نتیجه زنده سودآور نبوده است؛ به این سیگنال‌ها پول واقعی ندهید.';
  }
  if (s.stats.tStat >= 2.0) {
    return 'تا اینجا مثبت و از نظر آماری معنادار است؛ ولی همچنان فقط با مبلغ کم و ریسک ۱٪ ادامه دهید.';
  }
  return 'تا اینجا مثبت است ولی هنوز از نظر آماری معنادار نیست؛ صبر کنید و بیشتر ثبت کنید.';
}

String outcomeLabel(String o) {
  switch (o) {
    case 'tp2':
      return 'به هدف دوم رسید';
    case 'sl':
      return 'حد ضرر خورد';
    case 'tp1_be':
      return 'هدف اول، سپس سر‌به‌سر';
    case 'timeout':
      return 'پایان زمان نگهداری';
    default:
      return '';
  }
}
