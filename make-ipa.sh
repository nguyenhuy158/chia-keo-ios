#!/bin/bash
# Build ChiaKeo va dong goi .ipa KHONG ky vao build/. Sideloadly lo phan ky.
set -euo pipefail
cd "$(dirname "$0")"

xcodebuild -scheme ChiaKeo -sdk iphoneos -configuration Release \
  -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build > /tmp/chiakeo-build.log || { grep -E 'error:|BUILD FAILED' /tmp/chiakeo-build.log | head; exit 1; }

APP=build/dd/Build/Products/Release-iphoneos/ChiaKeo.app
[ -d "$APP" ] || { echo "ChiaKeo.app not found at $APP"; exit 1; }

rm -rf build/Payload && mkdir -p build/Payload
cp -R "$APP" build/Payload/
rm -f build/ChiaKeo.ipa
(cd build && zip -qry ChiaKeo.ipa Payload && rm -rf Payload)

echo "→ $(pwd)/build/ChiaKeo.ipa"
