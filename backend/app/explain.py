"""توضیح سیگنال: LLM رایگان (اختیاری) یا قالب پیش‌فرض. LLM هیچ عددی نمی‌سازد."""
import requests
from . import config


def template(s: dict) -> str:
    d = "خرید (Long)" if s["side"] == "LONG" else "فروش (Short)"
    st = s["backtest"]
    return (f"{s['symbol']} در تایم‌فریم {s['timeframe']} سیگنال {d} دارد؛ روند و مومنتوم هم‌جهت‌اند. "
            f"ورود {s['entry']:.6g}، حد ضرر {s['sl']:.6g}، هدف‌ها {s['tp1']:.6g} و {s['tp2']:.6g}. "
            f"در آزمون خارج از نمونه: {st['trades']} معامله، وین‌ریت {st['win_rate']}٪، "
            f"میانگین {st['expectancy_R']}R. این تحلیل توصیه مالی نیست؛ ریسک هر معامله را کوچک نگه دارید.")


def explain(s: dict) -> str:
    if not (config.LLM_BASE_URL and config.LLM_MODEL):
        return template(s)
    prompt = (
        "تو دستیار تحلیل کریپتو هستی. فقط با داده‌های زیر، در ۳ تا ۴ جمله فارسی سیگنال را توضیح بده. "
        "هیچ عدد جدیدی نساز و سود تضمین نکن. ریسک را هم ذکر کن.\n" + str(s))
    try:
        r = requests.post(
            config.LLM_BASE_URL.rstrip("/") + "/chat/completions",
            headers={"Authorization": f"Bearer {config.LLM_API_KEY}"},
            json={"model": config.LLM_MODEL, "messages": [{"role": "user", "content": prompt}],
                  "temperature": 0.2}, timeout=30)
        return r.json()["choices"][0]["message"]["content"].strip()
    except Exception:
        return template(s)
