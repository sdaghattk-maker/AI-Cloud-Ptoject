"""تنظیمات مرکزی پروژه"""
import os

SYMBOLS = ["BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT", "XRPUSDT",
           "ADAUSDT", "DOGEUSDT", "AVAXUSDT", "LINKUSDT", "TONUSDT"]
TIMEFRAMES = ["15m", "1h", "4h", "1d"]
CANDLES = 5000

BASE_URLS = ["https://api.binance.com", "https://data-api.binance.vision"]
CACHE_DIR = os.path.join(os.path.dirname(__file__), "..", "data")

FEE = 0.001        # کارمزد هر سمت (0.1%)
SLIPPAGE = 0.0003  # لغزش قیمت
MAX_HOLD = 100     # حداکثر کندل نگهداری معامله

# شبکه پارامترها برای بهینه‌سازی walk-forward
GRID = {
    "adx_min": [15, 20, 25],
    "atr_sl": [1.2, 1.5, 2.0],
    "rr2": [2.0, 3.0],
}
RR1 = 1.0  # هدف اول: 1R

# فیلتر کیفیت سیگنال (روی نتایج خارج از نمونه)
MIN_OOS_TRADES = 20
MIN_OOS_EXPECTANCY = 0.0  # میانگین R خالص باید مثبت باشد
MIN_PROFIT_FACTOR = 1.1

# LLM (اختیاری، هر سرویس سازگار با OpenAI: Groq / Gemini / Ollama)
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "")
LLM_API_KEY = os.getenv("LLM_API_KEY", "")
LLM_MODEL = os.getenv("LLM_MODEL", "")
