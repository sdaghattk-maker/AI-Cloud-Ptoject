import 'indicators.dart';

class Params {
  final double adxMin, atrSl, rr2;
  const Params(this.adxMin, this.atrSl, this.rr2);
}

class Signals {
  final List<int> side; // +1 لانگ، -1 شورت، 0 هیچ
  final List<double> score;
  Signals(this.side, this.score);
}

double _clip(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// روند + پولبک + تأیید مومنتوم/حجم. فقط به داده تا همان کندل نگاه می‌کند (بدون look-ahead).
Signals buildSignals(Indicators d, double adxMin) {
  final n = d.c.length;
  final side = List<int>.filled(n, 0);
  final score = List<double>.filled(n, 0);
  final close = d.c.close;
  for (var i = 200; i < n; i++) {
    final adx = d.adx[i], vr = d.volRatio[i], atr = d.atr[i];
    if (adx.isNaN || vr.isNaN || atr.isNaN || atr <= 0) continue;
    final strong = adx >= adxMin;
    final volOk = vr >= 0.6;
    if (!strong || !volOk) continue;

    final trendUp = d.ema50[i] > d.ema200[i] && close[i] > d.ema50[i];
    final trendDn = d.ema50[i] < d.ema200[i] && close[i] < d.ema50[i];
    final macdUp = d.macdH[i] > d.macdH[i - 1];
    final macdDn = d.macdH[i] < d.macdH[i - 1];

    final isLong = trendUp && macdUp && d.rsiMin5[i] < 48 &&
        d.rsi[i] > 50 && d.rsi[i - 1] <= 50;
    final isShort = trendDn && macdDn && d.rsiMax5[i] > 52 &&
        d.rsi[i] < 50 && d.rsi[i - 1] >= 50;
    if (!isLong && !isShort) continue;

    side[i] = isLong ? 1 : -1;
    score[i] = (40 +
            _clip((adx - adxMin) * 1.5, 0, 25) +
            _clip((vr - 1) * 15, 0, 20) +
            _clip(d.macdH[i].abs() / atr * 40, 0, 15))
        .roundToDouble();
  }
  return Signals(side, score);
}
