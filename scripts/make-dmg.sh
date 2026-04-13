#!/usr/bin/env bash
# Build Release .app and package a UDZO DMG.
#
# Default (local): xcodebuild Release → .app signed like in Xcode (Automatic signing).
#   Configure Team: Xcode → Signing & Capabilities, or project.local.yml (see project.local.yml.example),
#   or export DEVELOPMENT_TEAM=XXXXXXXXXX before running this script.
#
# CI / headless: set BUILD_WITH_SWIFT=1 to use swift build + manual .app bundle (no Apple account on runner).
#
# Optional ad-hoc / distribution re-sign after Swift path only:
#   export CODESIGN_IDENTITY="Developer ID Application: …"
#
# Usage: ./scripts/make-dmg.sh [version]
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

use_swift_build() {
	[[ "${BUILD_WITH_SWIFT:-}" == "1" || "${BUILD_WITH_SWIFT:-}" == "yes" || "${BUILD_WITH_SWIFT:-}" == "true" ]]
}

has_xcodeproj() {
	[[ -d "$ROOT/CoolifyDeployBar.xcodeproj" ]]
}

build_dmg_from_app() {
	local app_src="$1"
	local STAGE="$ROOT/build/dmg_stage"
	local APP_NAME="CoolifyDeployBar.app"
	local APP_PATH="$STAGE/$APP_NAME"

	rm -rf "$STAGE"
	mkdir -p "$STAGE"
	ditto "$app_src" "$APP_PATH"

	mkdir -p "$ROOT/dist"
	local DMG="$ROOT/dist/CoolifyDeployBar-${VERSION}.dmg"
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
}

if ! use_swift_build && has_xcodeproj; then
	echo "==> xcodebuild (Release, CODE_SIGN_STYLE=Automatic — same signing as Xcode)"
	DERIVED="$ROOT/build/xcode_derived"
	rm -rf "$DERIVED"

	XB=(
		xcodebuild
		-project "$ROOT/CoolifyDeployBar.xcodeproj"
		-scheme CoolifyDeployBar
		-configuration Release
		-derivedDataPath "$DERIVED"
		ONLY_ACTIVE_ARCH=NO
		CODE_SIGN_STYLE=Automatic
		"MARKETING_VERSION=$VERSION"
		"CURRENT_PROJECT_VERSION=$BUILD"
	)
	if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
		XB+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
	fi
	if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
		XB+=("CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY")
	fi
	XB+=(build)
	"${XB[@]}"

	APP_BUILD="$DERIVED/Build/Products/Release/CoolifyDeployBar.app"
	if [[ ! -d "$APP_BUILD" ]]; then
		echo "Build failed: $APP_BUILD not found" >&2
		exit 1
	fi

	build_dmg_from_app "$APP_BUILD"
	exit 0
fi

echo "==> swift build (Release) — BUILD_WITH_SWIFT=1 or no .xcodeproj"
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

echo "==> Assemble $APP_NAME (unsigned bundle)"
cp "$EXEC" "$APP_PATH/Contents/MacOS/CoolifyDeployBar"
chmod +x "$APP_PATH/Contents/MacOS/CoolifyDeployBar"

cp "$ROOT/Packaging/Info.plist" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP_PATH/Contents/Info.plist"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
	echo "==> codesign (identity: $CODESIGN_IDENTITY)"
	codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_PATH"
else
	echo "==> codesign skipped (set CODESIGN_IDENTITY for ad-hoc/Developer ID on this path)"
fi

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
