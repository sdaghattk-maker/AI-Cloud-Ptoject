import 'dart:math' as math;
import 'binance.dart';

/// EMA با آلفای 2/(n+1) (معادل pandas ewm span, adjust=false)
List<double> ema(List<double> s, int n) {
  final a = 2 / (n + 1);
  final out = List<double>.filled(s.length, 0);
  for (var i = 0; i < s.length; i++) {
    out[i] = i == 0 ? s[i] : a * s[i] + (1 - a) * out[i - 1];
  }
  return out;
}

/// میانگین وایلدر (alpha = 1/n)
List<double> wilder(List<double> s, int n) {
  final a = 1 / n;
  final out = List<double>.filled(s.length, 0);
  for (var i = 0; i < s.length; i++) {
    out[i] = i == 0 ? s[i] : a * s[i] + (1 - a) * out[i - 1];
  }
  return out;
}

List<double> rsi(List<double> close, int n) {
  final up = List<double>.filled(close.length, 0);
  final dn = List<double>.filled(close.length, 0);
  for (var i = 1; i < close.length; i++) {
    final d = close[i] - close[i - 1];
    up[i] = d > 0 ? d : 0;
    dn[i] = d < 0 ? -d : 0;
  }
  final u = wilder(up, n);
  final d = wilder(dn, n);
  return List<double>.generate(close.length, (i) {
    if (d[i] == 0) return u[i] > 0 ? 100.0 : 50.0;
    return 100 - 100 / (1 + u[i] / d[i]);
  });
}

List<double> trueRange(Candles c) {
  final out = List<double>.filled(c.length, 0);
  for (var i = 0; i < c.length; i++) {
    final hl = c.high[i] - c.low[i];
    if (i == 0) {
      out[i] = hl;
    } else {
      final pc = c.close[i - 1];
      out[i] = math.max(hl, math.max((c.high[i] - pc).abs(), (c.low[i] - pc).abs()));
    }
  }
  return out;
}

List<double> atr(Candles c, int n) => wilder(trueRange(c), n);

List<double> adx(Candles c, int n) {
  final len = c.length;
  final plus = List<double>.filled(len, 0);
  final minus = List<double>.filled(len, 0);
  for (var i = 1; i < len; i++) {
    final upMove = c.high[i] - c.high[i - 1];
    final dnMove = c.low[i - 1] - c.low[i];
    plus[i] = (upMove > dnMove && upMove > 0) ? upMove : 0;
    minus[i] = (dnMove > upMove && dnMove > 0) ? dnMove : 0;
  }
  final a = atr(c, n);
  final pa = wilder(plus, n);
  final ma = wilder(minus, n);
  final dx = List<double>.filled(len, 0);
  for (var i = 0; i < len; i++) {
    if (a[i] <= 0) continue;
    final pdi = 100 * pa[i] / a[i];
    final mdi = 100 * ma[i] / a[i];
    final s = pdi + mdi;
    dx[i] = s == 0 ? 0 : 100 * (pdi - mdi).abs() / s;
  }
  return wilder(dx, n);
}

List<double> macdHist(List<double> close) {
  final f = ema(close, 12);
  final s = ema(close, 26);
  final m = List<double>.generate(close.length, (i) => f[i] - s[i]);
  final sig = ema(m, 9);
  return List<double>.generate(close.length, (i) => m[i] - sig[i]);
}

class Indicators {
  final Candles c;
  final List<double> ema50, ema200, rsi, atr, adx, macdH, volRatio, rsiMin5, rsiMax5;
  Indicators({
    required this.c,
    required this.ema50,
    required this.ema200,
    required this.rsi,
    required this.atr,
    required this.adx,
    required this.macdH,
    required this.volRatio,
    required this.rsiMin5,
    required this.rsiMax5,
  });
}

Indicators computeIndicators(Candles c) {
  final n = c.length;
  final r = rsi(c.close, 14);
  final volRatio = List<double>.filled(n, double.nan);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    sum += c.volume[i];
    if (i >= 20) sum -= c.volume[i - 20];
    if (i >= 19) {
      final mean = sum / 20;
      volRatio[i] = mean > 0 ? c.volume[i] / mean : double.nan;
    }
  }
  final rmin = List<double>.filled(n, double.nan);
  final rmax = List<double>.filled(n, double.nan);
  for (var i = 4; i < n; i++) {
    var lo = double.infinity, hi = -double.infinity;
    for (var k = i - 4; k <= i; k++) {
      lo = math.min(lo, r[k]);
      hi = math.max(hi, r[k]);
    }
    rmin[i] = lo;
    rmax[i] = hi;
  }
  return Indicators(
    c: c,
    ema50: ema(c.close, 50),
    ema200: ema(c.close, 200),
    rsi: r,
    atr: atr(c, 14),
    adx: adx(c, 14),
    macdH: macdHist(c.close),
    volRatio: volRatio,
    rsiMin5: rmin,
    rsiMax5: rmax,
  );
}
