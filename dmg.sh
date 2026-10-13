#!/bin/zsh
# Paylaşılabilir DMG üretir: dist/Qmixer-<sürüm>.dmg (Qmixer.app + Applications kısayolu)
set -e
cd "$(dirname "$0")"
./build.sh --no-install

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG="dist/Qmixer-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R dist/Qmixer.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "KURULUM.txt" "$STAGE/KURULUM.txt"

rm -f "$DMG"
hdiutil create -volname "Qmixer $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
security find-certificate -c "Qmixer Local Signing" >/dev/null 2>&1 && codesign --force --sign "Qmixer Local Signing" "$DMG"
shasum -a 256 "$DMG"
echo "OK -> $PWD/$DMG"
