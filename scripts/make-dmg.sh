#!/usr/bin/env bash
# Build Release binary (SwiftPM), wrap a minimal .app bundle, package UDZO DMG.
# Usage: ./scripts/make-dmg.sh [version]
# version: e.g. 1.0.2 or v1.0.2 (defaults: GITHUB_REF_NAME, then 1.0.0 from Packaging/Info.plist)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

resolve_version() {
	local v="${GITHUB_REF_NAME:-}"
	v="${v#refs/tags/}"
	v="${v#v}"
	if [[ -n "${1:-}" ]]; then
		v="${1#v}"
	fi
	if [[ -z "$v" ]]; then
		v=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Packaging/Info.plist" 2>/dev/null || echo "1.0.0")
	fi
	echo "$v"
}

VERSION="$(resolve_version "${1:-}")"
BUILD="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

echo "==> swift build (Release)"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
EXEC="$BIN_DIR/CoolifyDeployBar"
if [[ ! -x "$EXEC" ]]; then
	echo "Build failed: $EXEC not found or not executable" >&2
	exit 1
fi

DERIVED="$ROOT/build"
STAGE="$DERIVED/dmg_stage"
APP_NAME="CoolifyDeployBar.app"
APP_PATH="$STAGE/$APP_NAME"

rm -rf "$STAGE"
mkdir -p "$APP_PATH/Contents/MacOS"

echo "==> Assemble $APP_NAME"
cp "$EXEC" "$APP_PATH/Contents/MacOS/CoolifyDeployBar"
chmod +x "$APP_PATH/Contents/MacOS/CoolifyDeployBar"

cp "$ROOT/Packaging/Info.plist" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP_PATH/Contents/Info.plist"

mkdir -p "$ROOT/dist"
DMG="$ROOT/dist/CoolifyDeployBar-${VERSION}.dmg"
rm -f "$DMG"

echo "==> hdiutil -> $DMG"
hdiutil create \
	-volname "CoolifyDeployBar ${VERSION}" \
	-srcfolder "$STAGE" \
	-ov \
	-format UDZO \
	"$DMG"

echo "Created: $DMG"
ls -la "$DMG"
