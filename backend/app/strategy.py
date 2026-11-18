"""استراتژی: دنبال‌کردن روند + پولبک + تأیید مومنتوم/حجم (قابل بک‌تست و کاملاً قطعی)"""
import numpy as np
import pandas as pd


def build_signals(d: pd.DataFrame, p: dict) -> pd.DataFrame:
    """
    خروجی: ستون side (+1 لانگ، -1 شورت، 0 هیچ) و score (0..100) برای هر کندل بسته‌شده.
    هیچ look-ahead ندارد: فقط از داده تا همان کندل استفاده می‌شود.
    """
    trend_up = (d["ema50"] > d["ema200"]) & (d["close"] > d["ema50"])
    trend_dn = (d["ema50"] < d["ema200"]) & (d["close"] < d["ema50"])
    strong = d["adx"] >= p["adx_min"]
    vol_ok = d["vol_ratio"] >= 0.6
    macd_up = d["macd_h"] > d["macd_h"].shift()
    macd_dn = d["macd_h"] < d["macd_h"].shift()

    # پولبک: RSI اخیراً زیر 48 رفته و حالا از 50 به بالا برگشته (برعکس برای شورت)
    long_ = trend_up & strong & vol_ok & macd_up & (d["rsi_min5"] < 48) \
        & (d["rsi"] > 50) & (d["rsi"].shift() <= 50)
    short_ = trend_dn & strong & vol_ok & macd_dn & (d["rsi_max5"] > 52) \
        & (d["rsi"] < 50) & (d["rsi"].shift() >= 50)

    side = np.where(long_, 1, np.where(short_, -1, 0))
    score = (40
             + np.clip((d["adx"] - p["adx_min"]) * 1.5, 0, 25)
             + np.clip((d["vol_ratio"] - 1) * 15, 0, 20)
             + np.clip(d["macd_h"].abs() / d["atr"] * 40, 0, 15))
    out = pd.DataFrame({"side": side, "score": score.round(0)}, index=d.index)
    out.loc[d[["ema200", "atr", "adx", "vol_ratio"]].isna().any(axis=1), "side"] = 0
    return out


def levels(row, side: int, p: dict, rr1: float):
    """سطوح معامله بر پایه ATR"""
    risk = p["atr_sl"] * row["atr"]
    e = row["close"]
    return {
        "entry": e,
        "sl": e - side * risk,
        "tp1": e + side * risk * rr1,
        "tp2": e + side * risk * p["rr2"],
        "risk_pct": risk / e * 100,
    }
