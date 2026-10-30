#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'Нужен macOS с Xcode. На Windows/Linux используйте workflow Build iPhone IPA в GitHub Actions.' >&2
  exit 1
fi
bash scripts/test.sh
xcodebuild -project ThomTroll.xcodeproj -scheme ThomTroll \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= ARCHS=arm64 build
python3 scripts/package_ipa.py
