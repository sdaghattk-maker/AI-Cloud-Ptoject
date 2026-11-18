import 'package:flutter_test/flutter_test.dart';
import 'package:cryptosignal/models/signal.dart';

void main() {
  final json = {
    'symbol': 'BTCUSDT',
    'timeframe': '1h',
    'side': 'LONG',
    'time': '2026-11-17 10:00:00+00:00',
    'score': 62.0,
    'entry': 100.0,
    'sl': 96.0,
    'tp1': 104.0,
    'tp2': 112.0,
    'risk_pct': 4.0,
    'explanation': 'تست',
    'backtest': {
      'trades': 30,
      'win_rate': 55.5,
      'expectancy_R': 0.21,
      'profit_factor': 1.4,
      'max_dd_R': 3.2,
      'total_R': 6.3
    },
  };

  test('Signal.fromJson parses fields and computes R:R', () {
    final s = Signal.fromJson(json);
    expect(s.isLong, true);
    expect(s.riskDistance, 4.0);
    expect(s.rr2, 3.0);
    expect(s.backtest.trades, 30);
  });

  test('AnalyzeResult handles null signal', () {
    final r = AnalyzeResult.fromJson({
      'symbol': 'ETHUSDT',
      'timeframe': '4h',
      'candles': 5000,
      'backtest': {'trades': 0},
      'signal': null,
    });
    expect(r.signal, isNull);
    expect(r.edgeOk, false);
  });

  test('fmt picks sensible precision', () {
    expect(fmt(65000.123), '65000.12');
    expect(fmt(0.123456789), '0.123457');
  });
}
