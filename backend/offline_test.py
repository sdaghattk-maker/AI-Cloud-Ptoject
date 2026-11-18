"""تست آفلاین با داده مصنوعی (برای اطمینان از سالم‌بودن کل پایپ‌لاین بدون اینترنت)"""
import numpy as np, pandas as pd
from app.analyzer import analyze

rng = np.random.default_rng(7)
n = 5000
drift = np.repeat(rng.normal(0, 0.0012, n // 250 + 1), 250)[:n]
ret = drift + rng.normal(0, 0.006, n)
close = 100 * np.exp(np.cumsum(ret))
open_ = np.r_[close[0], close[:-1]]
high = np.maximum(open_, close) * (1 + np.abs(rng.normal(0, 0.003, n)))
low = np.minimum(open_, close) * (1 - np.abs(rng.normal(0, 0.003, n)))
vol = rng.lognormal(10, 0.4, n)
df = pd.DataFrame({"time": pd.date_range("2024-01-01", periods=n, freq="1h", tz="UTC"),
                   "open": open_, "high": high, "low": low, "close": close, "volume": vol})
r = analyze("TESTUSDT", "1h", df=df)
print("OOS:", r["backtest"]); print("params:", r["params"]); print("edge_ok:", r.get("edge_ok"))
print("signal:", r["signal"])
