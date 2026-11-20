import 'dart:math' as math;
import '../models/signal.dart';
import 'indicators.dart';
import 'strategy.dart';

const double fee = 0.001; // کارمزد هر سمت
const double slippage = 0.0003;
const int maxHold = 100;
const double rr1 = 1.0;

/// حداکثر هزینه مجاز (کارمزد رفت‌وبرگشت + لغزش) بر حسب کسری از ریسک (R).
/// معامله‌ای که هزینه‌اش بیش از این باشد، از ابتدا ارزش ورود ندارد.
const double maxCostR = 0.25;

double costInR(double entry, double risk) =>
    risk > 0 ? (fee * 2 + slippage) * entry / risk : double.infinity;

class Trade {
  final double r; // نتیجه خالص (بعد از کارمزد و لغزش) بر حسب R
  final int bar, side, bars;
  final double costR; // هزینه کارمزد + لغزش بر حسب R؛ نتیجه خام = r + costR
  final double riskPct; // فاصله حد ضرر از ورود، درصد قیمت
  const Trade(this.r, this.bar, this.side, this.bars,
      [this.costR = 0, this.riskPct = 0]);
}

/// بک‌تست واقع‌گرایانه: ورود در open کندل بعد، اول SL (محافظه‌کارانه)،
/// نیمی در TP1 و انتقال SL به نقطه ورود، باقی تا TP2.
List<Trade> runBacktest(
    Indicators d, Signals sig, Params p, int start, int end) {
  final o = d.c.open, h = d.c.high, l = d.c.low, c = d.c.close;
  final trades = <Trade>[];
  var i = start;
  while (i < end - 2) {
    final s = sig.side[i];
    if (s == 0) {
      i++;
      continue;
    }
    final k0 = i + 1;
    final e = o[k0] * (1 + slippage * s);
    final risk = p.atrSl * d.atr[i];
    if (!(risk > 0) || costInR(e, risk) > maxCostR) {
      i++;
      continue;
    }
    final sl = e - s * risk;
    final tp1 = e + s * risk * rr1;
    final tp2 = e + s * risk * p.rr2;
    var rem = 1.0, pnl = 0.0;
    var done = false;
    var slCur = sl;
    final last = math.min(i + maxHold, end - 1);
    var k = k0;
    while (k <= last) {
      final hitSl = s == 1 ? l[k] <= slCur : h[k] >= slCur;
      if (hitSl) {
        pnl += rem * s * (slCur - e);
        rem = 0;
        break;
      }
      if (!done && (s == 1 ? h[k] >= tp1 : l[k] <= tp1)) {
        pnl += 0.5 * s * (tp1 - e);
        rem = 0.5;
        done = true;
        slCur = e;
      }
      if (done && (s == 1 ? h[k] >= tp2 : l[k] <= tp2)) {
        pnl += rem * s * (tp2 - e);
        rem = 0;
        break;
      }
      k++;
    }
    if (rem > 0) {
      final kk = math.min(k, last);
      pnl += rem * s * (c[kk] - e);
      k = kk;
    }
    final fees = fee * 2 * e;
    trades.add(Trade((pnl - fees) / risk, i, s, k - i,
        (fees + slippage * o[k0]) / risk, risk / e * 100));
    i = k + 1;
  }
  return trades;
}

double _round(double v, int digits) {
  final m = math.pow(10, digits).toDouble();
  return (v * m).round() / m;
}

BacktestStats statsOf(List<Trade> tr) {
  if (tr.isEmpty) {
    return const BacktestStats(
        trades: 0, winRate: 0, expectancyR: 0, profitFactor: 0, maxDdR: 0, totalR: 0);
  }
  var gp = 0.0, gl = 0.0, sum = 0.0, eq = 0.0, dd = 0.0;
  var peak = -double.infinity;
  var wins = 0;
  for (final t in tr) {
    final r = t.r;
    sum += r;
    if (r > 0) {
      gp += r;
      wins++;
    } else if (r < 0) {
      gl -= r;
    }
    eq += r;
    if (eq > peak) peak = eq;
    if (peak - eq > dd) dd = peak - eq;
  }
  final mean = sum / tr.length;
  var varSum = 0.0;
  for (final t in tr) {
    final dd = t.r - mean;
    varSum += dd * dd;
  }
  final sd = tr.length > 1 ? math.sqrt(varSum / (tr.length - 1)) : 0.0;
  final tStat = sd > 0 ? mean / (sd / math.sqrt(tr.length)) : 0.0;
  return BacktestStats(
    trades: tr.length,
    winRate: _round(wins / tr.length * 100, 1),
    expectancyR: _round(sum / tr.length, 3),
    profitFactor: gl > 0 ? _round(gp / gl, 2) : 99.0,
    maxDdR: _round(dd, 2),
    totalR: _round(sum, 2),
    tStat: _round(tStat, 2),
  );
}
