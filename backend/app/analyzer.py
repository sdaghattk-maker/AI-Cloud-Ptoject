"""تحلیل کامل یک نماد/تایم‌فریم و اسکنر بازار"""
from . import config, data
from .indicators import add_indicators
from .strategy import build_signals, levels
from .backtest import walk_forward
from .explain import explain


def analyze(symbol: str, tf: str, df=None, with_text=True):
    df = df if df is not None else data.load(symbol, tf)
    d = add_indicators(df)
    oos, p = walk_forward(d)
    res = {"symbol": symbol, "timeframe": tf, "candles": len(d), "backtest": oos,
           "params": p, "signal": None}
    if not p:
        return res
    sig = build_signals(d, p)
    last = d.iloc[-1]
    side = int(sig["side"].iloc[-1])
    ok = (oos["trades"] >= config.MIN_OOS_TRADES
          and oos["expectancy_R"] > config.MIN_OOS_EXPECTANCY
          and oos["profit_factor"] >= config.MIN_PROFIT_FACTOR)
    res["edge_ok"] = bool(ok)
    if side != 0 and ok:
        lv = levels(last, side, p, config.RR1)
        s = {"symbol": symbol, "timeframe": tf, "side": "LONG" if side == 1 else "SHORT",
             "time": str(last["time"]), "score": float(sig["score"].iloc[-1]),
             **{k: round(float(v), 8) for k, v in lv.items()},
             "backtest": oos, "params": p}
        if with_text:
            s["explanation"] = explain(s)
        res["signal"] = s
    return res


def scan(symbols=None, timeframes=None):
    out = []
    for sym in symbols or config.SYMBOLS:
        for tf in timeframes or config.TIMEFRAMES:
            try:
                r = analyze(sym, tf)
                if r["signal"]:
                    out.append(r["signal"])
            except Exception as e:
                print(f"[skip] {sym} {tf}: {e}")
    return sorted(out, key=lambda x: (x["backtest"]["expectancy_R"], x["score"]), reverse=True)
