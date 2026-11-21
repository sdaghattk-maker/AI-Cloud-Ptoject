#!/usr/bin/env sh
# اجرا از داخل پوشه mobile:  sh ../tools/ensure_android.sh
# 1) اگر پوشه android وجود ندارد آن را می‌سازد  2) مجوز اینترنت را اضافه می‌کند
# برای توسعه محلی با HTTP:  ALLOW_CLEARTEXT=1 sh ../tools/ensure_android.sh
set -e
if [ ! -d android ]; then
  flutter create --platforms=android,ios --project-name cryptosignal --org com.example .
fi
M=android/app/src/main/AndroidManifest.xml
if ! grep -q "android.permission.INTERNET" "$M"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$M"
fi
if [ "$ALLOW_CLEARTEXT" = "1" ] && ! grep -q usesCleartextTraffic "$M"; then
  sed -i 's#<application#<application android:usesCleartextTraffic="true"#' "$M"
fi
echo "android manifest ready"
