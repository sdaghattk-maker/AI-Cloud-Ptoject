import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.indicators import add_indicators
from app.strategy import build_signals
from app.backtest import run_backtest, stats, walk_forward
from app.analyzer import analyze


def synthetic(n=5000, seed=7):
    rng = np.random.default_rng(seed)
    drift = np.repeat(rng.normal(0, 0.0012, n // 250 + 1), 250)[:n]
    close = 100 * np.exp(np.cumsum(drift + rng.normal(0, 0.006, n)))
    open_ = np.r_[close[0], close[:-1]]
    high = np.maximum(open_, close) * (1 + np.abs(rng.normal(0, 0.003, n)))
    low = np.minimum(open_, close) * (1 - np.abs(rng.normal(0, 0.003, n)))
    return pd.DataFrame({
        "time": pd.date_range("2024-01-01", periods=n, freq="1h", tz="UTC"),
        "open": open_, "high": high, "low": low, "close": close,
        "volume": rng.lognormal(10, 0.4, n)})


def test_indicators_columns():
    d = add_indicators(synthetic(500))
    for c in ["ema200", "rsi", "atr", "adx", "macd_h", "vol_ratio"]:
        assert c in d.columns
    assert d["atr"].iloc[-1] > 0


def test_no_lookahead_in_signals():
    # سیگنال کندل i نباید با تغییر کندل‌های بعدی عوض شود
    df = synthetic(1500)
    p = {"adx_min": 20}
    full = build_signals(add_indicators(df), p)["side"].values
    cut = build_signals(add_indicators(df.iloc[:1000]), p)["side"].values
    assert (full[:1000] == cut).all()


def test_backtest_stats_and_levels():
    d = add_indicators(synthetic())
    p = {"adx_min": 15, "atr_sl": 1.5, "rr2": 2.0}
    tr = run_backtest(d, build_signals(d, p), p)
    st = stats(tr)
    assert st["trades"] > 0
    assert -1.5 < st["expectancy_R"] < 3  # در بازه منطقی


def test_walk_forward_and_analyze_shape():
    df = synthetic()
    oos, params = walk_forward(add_indicators(df))
    assert {"trades", "win_rate", "expectancy_R", "profit_factor"} <= set(oos)
    r = analyze("TESTUSDT", "1h", df=df, with_text=False)
    assert r["symbol"] == "TESTUSDT" and "backtest" in r
