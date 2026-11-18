double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();

/// فرمت عدد قیمت بر اساس بزرگی
String fmt(double v) {
  if (v >= 100) return v.toStringAsFixed(2);
  if (v >= 1) return v.toStringAsFixed(4);
  return v.toStringAsFixed(6);
}

class BacktestStats {
  final int trades;
  final double winRate, expectancyR, profitFactor, maxDdR, totalR;

  const BacktestStats({
    required this.trades,
    required this.winRate,
    required this.expectancyR,
    required this.profitFactor,
    required this.maxDdR,
    required this.totalR,
  });

  factory BacktestStats.fromJson(Map<String, dynamic> j) => BacktestStats(
        trades: ((j['trades'] ?? 0) as num).toInt(),
        winRate: _d(j['win_rate']),
        expectancyR: _d(j['expectancy_R']),
        profitFactor: _d(j['profit_factor']),
        maxDdR: _d(j['max_dd_R']),
        totalR: _d(j['total_R']),
      );
}

class Signal {
  final String symbol, timeframe, side, time, explanation;
  final double score, entry, sl, tp1, tp2, riskPct;
  final BacktestStats backtest;

  const Signal({
    required this.symbol,
    required this.timeframe,
    required this.side,
    required this.time,
    required this.explanation,
    required this.score,
    required this.entry,
    required this.sl,
    required this.tp1,
    required this.tp2,
    required this.riskPct,
    required this.backtest,
  });

  bool get isLong => side == 'LONG';
  double get riskDistance => (entry - sl).abs();
  double get rr2 => riskDistance == 0 ? 0 : (tp2 - entry).abs() / riskDistance;

  factory Signal.fromJson(Map<String, dynamic> j) => Signal(
        symbol: j['symbol'] as String,
        timeframe: j['timeframe'] as String,
        side: j['side'] as String,
        time: (j['time'] ?? '') as String,
        explanation: (j['explanation'] ?? '') as String,
        score: _d(j['score']),
        entry: _d(j['entry']),
        sl: _d(j['sl']),
        tp1: _d(j['tp1']),
        tp2: _d(j['tp2']),
        riskPct: _d(j['risk_pct']),
        backtest: BacktestStats.fromJson(
            (j['backtest'] ?? <String, dynamic>{}) as Map<String, dynamic>),
      );
}

class AnalyzeResult {
  final String symbol, timeframe;
  final int candles;
  final bool edgeOk;
  final BacktestStats backtest;
  final Signal? signal;

  const AnalyzeResult({
    required this.symbol,
    required this.timeframe,
    required this.candles,
    required this.edgeOk,
    required this.backtest,
    required this.signal,
  });

  factory AnalyzeResult.fromJson(Map<String, dynamic> j) => AnalyzeResult(
        symbol: j['symbol'] as String,
        timeframe: j['timeframe'] as String,
        candles: ((j['candles'] ?? 0) as num).toInt(),
        edgeOk: (j['edge_ok'] ?? false) as bool,
        backtest: BacktestStats.fromJson(
            (j['backtest'] ?? <String, dynamic>{}) as Map<String, dynamic>),
        signal: j['signal'] == null
            ? null
            : Signal.fromJson(j['signal'] as Map<String, dynamic>),
      );
}
