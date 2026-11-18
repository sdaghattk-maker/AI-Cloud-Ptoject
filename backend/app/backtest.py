"""بک‌تست واقع‌گرایانه + Walk-Forward"""
import itertools
import numpy as np
import pandas as pd
from . import config
from .strategy import build_signals


def run_backtest(d, sig, p, start=0, end=None, rr1=config.RR1):
    end = end or len(d)
    o, h, l, c = (d[x].values for x in ("open", "high", "low", "close"))
    atr = d["atr"].values
    side_arr = sig["side"].values
    trades, i = [], start
    while i < end - 2:
        s = side_arr[i]
        if s == 0:
            i += 1
            continue
        k0 = i + 1
        e = o[k0] * (1 + config.SLIPPAGE * s)           # ورود در open کندل بعد
        risk = p["atr_sl"] * atr[i]
        if not risk > 0:
            i += 1
            continue
        sl, tp1, tp2 = e - s * risk, e + s * risk * rr1, e + s * risk * p["rr2"]
        rem, pnl, done, sl_cur = 1.0, 0.0, False, sl
        last = min(i + config.MAX_HOLD, end - 1)
        k = k0
        while k <= last:
            hit_sl = l[k] <= sl_cur if s == 1 else h[k] >= sl_cur
            if hit_sl:                                   # محافظه‌کارانه: اول SL
                pnl += rem * s * (sl_cur - e)
                rem = 0
                break
            if not done and ((h[k] >= tp1) if s == 1 else (l[k] <= tp1)):
                pnl += 0.5 * s * (tp1 - e)
                rem, done, sl_cur = 0.5, True, e         # نیمی ببند، SL به نقطه سر‌به‌سر
            if done and ((h[k] >= tp2) if s == 1 else (l[k] <= tp2)):
                pnl += rem * s * (tp2 - e)
                rem = 0
                break
            k += 1
        if rem > 0:
            kk = min(k, last)
            pnl += rem * s * (c[kk] - e)
            k = kk
        fees = config.FEE * 2 * e
        trades.append({"bar": i, "side": int(s), "R": (pnl - fees) / risk, "bars": k - i})
        i = k + 1
    return pd.DataFrame(trades)


def stats(tr: pd.DataFrame) -> dict:
    if tr is None or tr.empty:
        return {"trades": 0, "win_rate": 0, "expectancy_R": 0, "profit_factor": 0,
                "max_dd_R": 0, "total_R": 0}
    r = tr["R"]
    gp, gl = r[r > 0].sum(), -r[r < 0].sum()
    eq = r.cumsum()
    return {
        "trades": int(len(r)),
        "win_rate": round(float((r > 0).mean() * 100), 1),
        "expectancy_R": round(float(r.mean()), 3),
        "profit_factor": round(float(gp / gl), 2) if gl > 0 else 99.0,
        "max_dd_R": round(float((eq.cummax() - eq).max()), 2),
        "total_R": round(float(r.sum()), 2),
    }


def _grid():
    keys = list(config.GRID)
    for vals in itertools.product(*config.GRID.values()):
        yield dict(zip(keys, vals))


def optimize(d, start, end, min_trades=10):
    best, best_score = None, -1e9
    for p in _grid():
        sig = build_signals(d, p)
        st = stats(run_backtest(d, sig, p, start, end))
        if st["trades"] < min_trades:
            continue
        # امتیاز: میانگین R با جریمه برای تعداد کم معامله (جلوگیری از overfit)
        score = st["expectancy_R"] * np.sqrt(st["trades"])
        if score > best_score:
            best, best_score = p, score
    return best


def walk_forward(d, train=2000, test=500):
    """روی پنجره آموزش بهینه می‌کند و روی پنجره بعدی (دیده‌نشده) تست می‌کند."""
    all_oos, start = [], 200  # 200 کندل اول برای گرم‌شدن اندیکاتورها
    while start + train + test <= len(d):
        p = optimize(d, start, start + train)
        if p:
            sig = build_signals(d, p)
            tr = run_backtest(d, sig, p, start + train, start + train + test)
            all_oos.append(tr)
        start += test
    oos = pd.concat(all_oos, ignore_index=True) if all_oos else pd.DataFrame()
    final_p = optimize(d, max(200, len(d) - train), len(d))
    return stats(oos), final_p
