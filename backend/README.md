# CryptoSignal AI — مرحله ۱: هسته تحلیل (بک‌اند)

## اجرا
    pip install -r requirements.txt
    python offline_test.py                    # تست بدون اینترنت (داده مصنوعی)
    uvicorn app.api:app --host 0.0.0.0 --port 8000

## Endpointها
- GET /health
- GET /analyze?symbol=BTCUSDT&tf=1h   تحلیل کامل + بک‌تست walk-forward + سیگنال (در صورت وجود)
- GET /scan                           اسکن همه نمادها و تایم‌فریم‌ها، مرتب بر اساس کیفیت

## LLM رایگان (اختیاری) — متغیرهای محیطی
    LLM_BASE_URL=https://api.groq.com/openai/v1   (یا Gemini سازگار با OpenAI، یا http://localhost:11434/v1 برای Ollama)
    LLM_API_KEY=...
    LLM_MODEL=...
بدون این‌ها، توضیح با قالب پیش‌فرض ساخته می‌شود.

## نکته مهم
سیگنال فقط وقتی داده می‌شود که نتیجه Walk-Forward روی داده‌های دیده‌نشده مثبت باشد
(حداقل ۲۰ معامله، میانگین R > 0، پروفیت فاکتور ≥ 1.1). در غیر این صورت «بدون سیگنال».
