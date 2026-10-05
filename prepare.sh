#!/usr/bin/env bash
# מסדר את הקבצים, יוצר את תיקיות הפלטפורמה ומגדיר הרשאות ושם
set -e
cd "$(dirname "$0")"
[ -f pubspec.yaml ] || cd ..

# קבצים שהועלו בלי תיקיות
mkdir -p lib assets
for f in *.dart; do [ -e "$f" ] && mv "$f" lib/; done
for f in icon.png icon_fg.png; do if [ -f "$f" ]; then mv "$f" assets/; fi; done

if [ ! -d android ] || [ ! -d ios ]; then
  flutter create --org il.lior --project-name samsung_remote --platforms=android,ios .
  rm -rf test
fi

flutter pub get

M=android/app/src/main/AndroidManifest.xml
if [ -f "$M" ]; then
  grep -q 'android.permission.INTERNET' "$M" || \
    perl -0pi -e 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>\n    <application#' "$M"
  perl -0pi -e 's#android:label="[^"]*"#android:label="שלט סמסונג"#' "$M"
  # חיבור HTTP לא מוצפן לטלוויזיה ברשת הביתית
  grep -q 'usesCleartextTraffic' "$M" || \
    perl -0pi -e 's#<application#<application android:usesCleartextTraffic="true"#' "$M"
fi

P=ios/Runner/Info.plist
if [ -f "$P" ] && [ -x /usr/libexec/PlistBuddy ]; then
  /usr/libexec/PlistBuddy -c "Delete :NSLocalNetworkUsageDescription" "$P" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string השלט צריך גישה לרשת הביתית כדי להתחבר לטלוויזיות" "$P"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName שלט סמסונג" "$P" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string שלט סמסונג" "$P"
fi

dart run flutter_launcher_icons || echo "icons step skipped"
