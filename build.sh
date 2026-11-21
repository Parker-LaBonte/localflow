#!/bin/zsh
# Build LocalFlow.app.
#
#   ./build.sh             build into ~/Applications and launch it
#   ./build.sh --no-launch build only
#   ./build.sh --release   ad-hoc signed build in dist/, zipped for a GitHub release
#
# Needs Xcode command line tools and Homebrew's whisper.cpp + llama.cpp (their servers are bundled into the app):
#   brew install whisper-cpp llama.cpp
#
# Optional, git-ignored .build.local can set BUNDLE_ID and SIGN_IDENTITY for your own builds
# (a stable identity keeps macOS permissions across rebuilds).
set -e
cd "$(dirname "$0")"

RELEASE=0; LAUNCH=1
for a in "$@"; do
  case $a in
    --release) RELEASE=1; LAUNCH=0 ;;
    --no-launch) LAUNCH=0 ;;
  esac
done

BUNDLE_ID="app.localflow.mac"
SIGN_IDENTITY="-"   # ad-hoc
[[ $RELEASE == 0 && -f .build.local ]] && source ./.build.local

if [[ $RELEASE == 1 ]]; then APP=dist/LocalFlow.app; else APP=~/Applications/LocalFlow.app; fi

[[ $RELEASE == 0 ]] && { pkill -x LocalFlow 2>/dev/null || true; sleep 0.5; }
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/LocalFlow" -target arm64-apple-macos14.0 \
  -framework Cocoa -framework SwiftUI -framework Charts -framework AVFoundation -framework ServiceManagement -framework CoreML

cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
cp -R resources/LocalFlowXS.mlmodelc resources/xs-vocab.txt resources/AppIcon.icns "$APP/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
python3 tools/bundle_engines.py "$APP"

# Sign inside-out: engine libraries and helpers, then the app.
OPTS=(--force --timestamp=none --sign "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" != "-" ]] && OPTS+=(--options runtime)
for f in "$APP"/Contents/Frameworks/* "$APP"/Contents/Helpers/*; do codesign "${OPTS[@]}" "$f"; done
codesign "${OPTS[@]}" --entitlements entitlements.plist "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"

if [[ $RELEASE == 1 ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
  rm -f dist/LocalFlow.zip
  ditto -c -k --keepParent "$APP" dist/LocalFlow.zip
  echo "Release: dist/LocalFlow.zip (v$VERSION, $(du -h dist/LocalFlow.zip | cut -f1))"
fi
[[ $LAUNCH == 1 ]] && open "$APP"
true
