# CryptoSignal AI

    backend/   تحلیل (FastAPI + پایتون): بایننس ← اندیکاتور ← سیگنال ← بک‌تست Walk-Forward
    mobile/    اپ Flutter (اندروید/iOS)
    tools/     اسکریپت آماده‌سازی پروژه اندروید
    .github/   CI: تست بک‌اند + آنالیز/تست/بیلد APK + اسکن زمان‌بندی‌شده

## نسخه بدون سرور (پیشنهادی)
اپ خودش داده را از بایننس می‌گیرد و تحلیل/بک‌تست را روی گوشی انجام می‌دهد (پوشه mobile/lib/engine).
فقط کافی است APK را از GitHub Actions بگیرید و نصب کنید؛ پوشه backend اختیاری است.

## هوش مصنوعی و یادگیری ماشین (داخل اپ)
- فیلتر ML: رگرسیون لجستیک روی معاملات تاریخی همه نمادها (هر تایم‌فریم)، با Walk-Forward و آزمون t.
  فقط در صورت برتری معنادار روی داده دیده‌نشده سیگنال‌ها را فیلتر می‌کند. (mobile/lib/ml)
- تحلیل AI: تا دو سرویس (Gemini/Groq یا هر API سازگار با OpenAI)، حالت خودکار یا مقایسه؛ هم برای سیگنال و هم برای توضیح «چرا سیگنالی نیست». (mobile/lib/services/llm.dart)

## اجرای محلی (اختیاری)
1) بک‌اند
    cd backend && pip install -r requirements.txt
    python -m pytest -q tests
    uvicorn app.api:app --host 0.0.0.0 --port 8000

2) اپ (نیازمند Flutter SDK)
    cd mobile
    ALLOW_CLEARTEXT=1 sh ../tools/ensure_android.sh   # ساخت پوشه android + مجوز اینترنت (+ HTTP برای توسعه)
    flutter pub get
    flutter run
آدرس سرور در تب «تنظیمات» اپ: شبیه‌ساز = http://10.0.2.2:8000 ، گوشی واقعی = http://IP-کامپیوتر:8000

## GitHub Actions
- ci.yml: روی هر push/PR → تست بک‌اند، flutter analyze، flutter test، ساخت APK (artifact).
  (نسخه CI بدون ALLOW_CLEARTEXT ساخته می‌شود؛ برای انتشار از HTTPS استفاده کنید.)
- scan.yml: اسکن ساعتی بازار و ذخیره signals.json (فقط برای آزمایش؛ سرور دائمی نیست).

## هشدار
ابزار کمک‌تحلیل است، نه توصیه مالی. سود تضمینی وجود ندارد.
