import '../engine/indicators.dart';

double _clip(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// ویژگی‌های جهت‌دار (برای لانگ و شورت قابل‌مقایسه‌اند) در کندل سیگنال.
/// فقط از داده تا همان کندل استفاده می‌شود.
List<double> featuresAt(Indicators d, int i, int side, {int strategy = 0}) {
  final close = d.c.close[i];
  final atr = d.atr[i];
  final s = side.toDouble();
  return [
    d.adx[i] / 50,
    _clip(d.volRatio[i], 0, 4) / 2,
    s * (d.rsi[i] - 50) / 25,
    _clip(s * d.macdH[i] / atr, -2, 2),
    _clip(s * (close - d.ema50[i]) / atr, -6, 6) / 3,
    _clip(s * (d.ema50[i] - d.ema200[i]) / atr, -20, 20) / 10,
    _clip(atr / close * 100, 0, 10) / 2,
    side == 1 ? (50 - d.rsiMin5[i]) / 50 : (d.rsiMax5[i] - 50) / 50,
    strategy == 1 ? 1.0 : 0.0, // شکست کانال
    strategy == 2 ? 1.0 : 0.0, // بازگشت به میانگین
  ];
}
