#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-build}"

case "$MODE" in
  build|install) ;;
  *) echo "usage: $0 [build|install]" >&2; exit 64 ;;
esac

BUNDLE_ID="${MOBILE_BRIDGE_BUNDLE_ID:-me.badia.ailimits.collector}"
CONTAINER_ID="${MOBILE_BRIDGE_ICLOUD_CONTAINER_ID:-iCloud.me.badia.ailimits}"
SIGNING_IDENTITY="${MOBILE_BRIDGE_SIGNING_IDENTITY:-Developer ID Application: Jesus Badia Closa (9L2TD7KVV9)}"
MARKETING_VERSION="${MOBILE_BRIDGE_MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${MOBILE_BRIDGE_BUILD_NUMBER:-1}"
APP_NAME="OpenUsage Mobile Bridge"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
RESOLVED_ENTITLEMENTS="$ROOT_DIR/dist/OpenUsage.mobile-bridge.resolved.entitlements.plist"
PROFILE="${MOBILE_BRIDGE_PROVISIONING_PROFILE:-}"

if [[ -z "$PROFILE" ]]; then
  PROFILE="$("$ROOT_DIR/script/find_icloud_provisioning_profile.sh" "$BUNDLE_ID" "$CONTAINER_ID")" || {
    echo "No current Developer ID profile matches $BUNDLE_ID and $CONTAINER_ID." >&2
    exit 1
  }
fi
[[ -f "$PROFILE" ]] || { echo "Provisioning profile not found: $PROFILE" >&2; exit 1; }

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  /usr/bin/swift build --package-path "$ROOT_DIR" -c release --product openusage-mobile-bridge
BIN_DIR="$(DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  /usr/bin/swift build --package-path "$ROOT_DIR" -c release --show-bin-path)"

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$MACOS_DIR"
/usr/bin/ditto "$BIN_DIR/openusage-mobile-bridge" "$MACOS_DIR/openusage-mobile-bridge"
/bin/chmod 755 "$MACOS_DIR/openusage-mobile-bridge"
/usr/bin/ditto "$PROFILE" "$CONTENTS_DIR/embedded.provisionprofile"

/usr/bin/plutil -create xml1 "$INFO_PLIST"
/usr/libexec/PlistBuddy \
  -c "Add :CFBundleDevelopmentRegion string en" \
  -c "Add :CFBundleDisplayName string $APP_NAME" \
  -c "Add :CFBundleExecutable string openusage-mobile-bridge" \
  -c "Add :CFBundleIdentifier string $BUNDLE_ID" \
  -c "Add :CFBundleInfoDictionaryVersion string 6.0" \
  -c "Add :CFBundleName string $APP_NAME" \
  -c "Add :CFBundlePackageType string APPL" \
  -c "Add :CFBundleShortVersionString string $MARKETING_VERSION" \
  -c "Add :CFBundleVersion string $BUILD_NUMBER" \
  -c "Add :LSMinimumSystemVersion string 15.0" \
  -c "Add :LSUIElement bool true" \
  -c "Add :NSHighResolutionCapable bool true" \
  -c "Add :NSPrincipalClass string NSApplication" \
  "$INFO_PLIST"
/usr/bin/plutil -insert NSUbiquitousContainers -json \
  "{\"$CONTAINER_ID\":{\"NSUbiquitousContainerIsDocumentScopePublic\":false,\"NSUbiquitousContainerName\":\"OpenUsage\",\"NSUbiquitousContainerSupportedFolderLevels\":\"None\"}}" \
  "$INFO_PLIST"

"$ROOT_DIR/script/render_icloud_entitlements.sh" \
  "$ROOT_DIR/script/OpenUsage.mobile-bridge.entitlements.plist" \
  "$PROFILE" \
  "$RESOLVED_ENTITLEMENTS" \
  "$CONTAINER_ID"

/usr/bin/codesign --force --timestamp --options runtime \
  --entitlements "$RESOLVED_ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_DIR" || true

echo "Built and signed: $APP_DIR"

if [[ "$MODE" == "install" ]]; then
  INSTALL_DIR="/Applications/$APP_NAME.app"
  /usr/bin/pkill -x openusage-mobile-bridge 2>/dev/null || true
  /bin/rm -rf "$INSTALL_DIR"
  /usr/bin/ditto "$APP_DIR" "$INSTALL_DIR"
  /usr/bin/open "$INSTALL_DIR"
  echo "Installed and launched: $INSTALL_DIR"
fi
