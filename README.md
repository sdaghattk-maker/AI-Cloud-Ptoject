# CryptoSignal AI

    backend/   تحلیل (FastAPI + پایتون): بایننس ← اندیکاتور ← سیگنال ← بک‌تست Walk-Forward
    mobile/    اپ Flutter (اندروید/iOS)
    tools/     اسکریپت آماده‌سازی پروژه اندروید
    .github/   CI: تست بک‌اند + آنالیز/تست/بیلد APK + اسکن زمان‌بندی‌شده

## اجرای محلی
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
