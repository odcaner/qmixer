#!/bin/zsh
# Qmixer.app derler (Apple Silicon + Intel), imzalar ve /Applications'a kurar.
#   ./build.sh               derle + kur + çalıştır
#   ./build.sh --no-install  sadece dist/Qmixer.app
set -e
cd "$(dirname "$0")"

# Yerel imza sertifikası varsa onu kullan (izinler derlemeler arası korunur), yoksa ad-hoc.
SIGN_ID="Qmixer Local Signing"
security find-certificate -c "$SIGN_ID" >/dev/null 2>&1 || SIGN_ID="-"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/Qmixer"

APP=dist/Qmixer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Qmixer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$SIGN_ID" --identifier com.canerod.qmixer "$APP"
codesign --verify --strict "$APP"

if [[ "$1" != "--no-install" ]]; then
    pkill -x Qmixer 2>/dev/null && sleep 1 || true
    rm -rf /Applications/Qmixer.app
    cp -R "$APP" /Applications/Qmixer.app
    open /Applications/Qmixer.app
    echo "OK -> /Applications/Qmixer.app (çalıştırıldı)"
else
    echo "OK -> $PWD/$APP"
fi
