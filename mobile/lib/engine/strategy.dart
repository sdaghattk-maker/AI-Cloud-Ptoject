import 'dart:math' as math;
import 'indicators.dart';

const strategyNames = [
  'روند + پولبک',
  'شکست کانال (Donchian)',
  'بازگشت به میانگین (بولینگر)',
];

class Params {
  final double adxMin, atrSl, rr2;
  final int strategy; // 0 پولبک روند، 1 شکست کانال، 2 بازگشت به میانگین
  final double param; // استراتژی ۱: طول کانال | استراتژی ۲: سقف ADX (برای ۰ همان adxMin)
  const Params(this.adxMin, this.atrSl, this.rr2, {this.strategy = 0, this.param = 0});

  /// کلید یکتای مجموعه سیگنال (فقط به استراتژی و پارامتر ورودی بستگی دارد)
  String get key => strategy == 0
      ? '0:${adxMin.toStringAsFixed(0)}'
      : '$strategy:${param.toStringAsFixed(0)}';

  String get strategyName => strategyNames[strategy];
}

class Signals {
  final List<int> side; // +1 لانگ، -1 شورت، 0 هیچ
  final List<double> score;
  Signals(this.side, this.score);
}

double _clip(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// ۰) روند + پولبک + تأیید مومنتوم/حجم. فقط به داده تا همان کندل نگاه می‌کند (بدون look-ahead).
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

/// ۱) شکست کانال دونچیان در جهت روند بلندمدت (EMA200) با ADX و حجم کافی.
/// کانال از [lookback] کندل «قبل از» کندل فعلی ساخته می‌شود و فقط اولین شکست حساب می‌شود.
Signals buildBreakout(Indicators d, int lookback) {
  final n = d.c.length;
  final side = List<int>.filled(n, 0);
  final score = List<double>.filled(n, 0);
  final h = d.c.high, l = d.c.low, c = d.c.close;
  for (var i = math.max(200, lookback + 2); i < n; i++) {
    final adx = d.adx[i], vr = d.volRatio[i], atr = d.atr[i];
    if (adx.isNaN || vr.isNaN || atr.isNaN || atr <= 0) continue;
    if (adx < 18 || vr < 1.0) continue;

    var hh = -double.infinity, ll = double.infinity;
    for (var k = i - lookback; k < i; k++) {
      if (h[k] > hh) hh = h[k];
      if (l[k] < ll) ll = l[k];
    }
    var hhPrev = -double.infinity, llPrev = double.infinity;
    for (var k = i - 1 - lookback; k < i - 1; k++) {
      if (h[k] > hhPrev) hhPrev = h[k];
      if (l[k] < llPrev) llPrev = l[k];
    }
    final isLong = c[i] > hh && c[i] > d.ema200[i] && c[i - 1] <= hhPrev;
    final isShort = c[i] < ll && c[i] < d.ema200[i] && c[i - 1] >= llPrev;
    if (!isLong && !isShort) continue;

    side[i] = isLong ? 1 : -1;
    score[i] = (40 +
            _clip((adx - 18) * 1.5, 0, 25) +
            _clip((vr - 1) * 15, 0, 20) +
            _clip((c[i] - c[i - 1]).abs() / atr * 10, 0, 15))
        .roundToDouble();
  }
  return Signals(side, score);
}

/// ۲) بازگشت به میانگین در بازار رنج (ADX پایین): برگشت قیمت به داخل باند بولینگر
/// بعد از خروج از آن، با تأیید RSI.
Signals buildReversion(Indicators d, double adxMax) {
  final n = d.c.length;
  final side = List<int>.filled(n, 0);
  final score = List<double>.filled(n, 0);
  final c = d.c.close;
  for (var i = 200; i < n; i++) {
    final adx = d.adx[i], atr = d.atr[i];
    if (adx.isNaN || atr.isNaN || atr <= 0 || adx > adxMax) continue;
    final lo = d.bbLo[i], lo1 = d.bbLo[i - 1], up = d.bbUp[i], up1 = d.bbUp[i - 1];
    if (lo.isNaN || lo1.isNaN || up.isNaN || up1.isNaN) continue;

    final isLong = c[i - 1] < lo1 && c[i] > lo && d.rsi[i] < 45;
    final isShort = c[i - 1] > up1 && c[i] < up && d.rsi[i] > 55;
    if (!isLong && !isShort) continue;

    final vr = d.volRatio[i].isNaN ? 1.0 : d.volRatio[i];
    final stretch = isLong ? 45 - d.rsi[i] : d.rsi[i] - 55;
    side[i] = isLong ? 1 : -1;
    score[i] = (40 +
            _clip(adxMax - adx, 0, 20) +
            _clip((vr - 1) * 15, 0, 20) +
            _clip(stretch, 0, 15))
        .roundToDouble();
  }
  return Signals(side, score);
}

Signals buildFor(Indicators d, Params p) {
  switch (p.strategy) {
    case 1:
      return buildBreakout(d, p.param.round());
    case 2:
      return buildReversion(d, p.param);
    default:
      return buildSignals(d, p.adxMin);
  }
}
