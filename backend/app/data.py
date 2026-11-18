"""دریافت ۵۰۰۰ کندل از بایننس (صفحه‌بندی ۱۰۰۰تایی) + کش"""
import os, time
import pandas as pd
import requests
from . import config

COLS = ["open_time", "open", "high", "low", "close", "volume", "close_time",
        "qav", "trades", "tbb", "tbq", "ignore"]


def _get(path, params):
    last = None
    for base in config.BASE_URLS:
        try:
            r = requests.get(base + path, params=params, timeout=15)
            if r.status_code == 200:
                return r.json()
            last = f"{base}: HTTP {r.status_code}"
        except requests.RequestException as e:
            last = f"{base}: {e}"
    raise RuntimeError(f"Binance request failed ({last})")


def fetch_klines(symbol: str, interval: str, total: int = config.CANDLES) -> pd.DataFrame:
    rows, end_time = [], None
    while len(rows) < total:
        params = {"symbol": symbol, "interval": interval, "limit": 1000}
        if end_time:
            params["endTime"] = end_time
        batch = _get("/api/v3/klines", params)
        if not batch:
            break
        rows = batch + rows
        end_time = batch[0][0] - 1
        if len(batch) < 1000:
            break
        time.sleep(0.15)  # رعایت rate limit
    df = pd.DataFrame(rows[-total:], columns=COLS)
    for c in ["open", "high", "low", "close", "volume"]:
        df[c] = df[c].astype(float)
    df["time"] = pd.to_datetime(df["open_time"], unit="ms", utc=True)
    df = df[["time", "open", "high", "low", "close", "volume", "close_time"]]
    # کندل آخر هنوز بسته نشده؛ حذفش می‌کنیم
    now_ms = int(time.time() * 1000)
    if len(df) and df["close_time"].iloc[-1] > now_ms:
        df = df.iloc[:-1]
    return df.drop(columns="close_time").reset_index(drop=True)


def load(symbol: str, interval: str, total: int = config.CANDLES, max_age_s: int = 300):
    os.makedirs(config.CACHE_DIR, exist_ok=True)
    path = os.path.join(config.CACHE_DIR, f"{symbol}_{interval}.csv")
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < max_age_s:
        return pd.read_csv(path, parse_dates=["time"])
    df = fetch_klines(symbol, interval, total)
    df.to_csv(path, index=False)
    return df
