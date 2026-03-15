#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./build_app.sh [--configuration release|debug] [--bundle-id com.example.filelay] [--output-dir dist] [--sign-identity "Developer ID Application: ..."] [--skip-sign]

Description:
  Build Filelay and package it as a standalone macOS app bundle.
USAGE
}

CONFIGURATION="release"
BUNDLE_ID="com.ajilin.filelay"
OUTPUT_DIR="dist"
APP_NAME="Filelay"
SIGN_IDENTITY=""
SKIP_SIGN=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$SCRIPT_DIR"
CACHE_DIR="$PACKAGE_ROOT/.build-cache/clang/ModuleCache"
STAGING_DIR=""
SAFE_EXPORT_DIR=""
SAFE_APP_ROOT=""
SAFE_ZIP_PATH=""
FINAL_SIGNATURE_STATUS="not_checked"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --sign-identity)
      SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    --skip-sign)
      SKIP_SIGN=1
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
  echo "Unsupported configuration: $CONFIGURATION" >&2
  exit 1
fi

extract_constant() {
  local label="$1"
  sed -nE "s/.*$label = \"([^\"]+)\".*/\\1/p" "$PACKAGE_ROOT/Sources/Filelay/BuildInfo.swift" | head -n 1
}

detect_sign_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/.*"([^"]*Developer ID Application:[^"]*)".*/\1/p' \
    | head -n 1
}

cleanup() {
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    rm -rf "$STAGING_DIR"
  fi
}

trap cleanup EXIT

APP_VERSION="$(extract_constant fallbackVersion)"
APP_BUILD="$(extract_constant fallbackBuild)"

if [[ -z "$APP_VERSION" || -z "$APP_BUILD" ]]; then
  echo "Failed to determine version/build from Sources/Filelay/BuildInfo.swift" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$CACHE_DIR"

swift build -c "$CONFIGURATION"

BINARY_PATH="$(find "$PACKAGE_ROOT/.build" -path "*/$CONFIGURATION/$APP_NAME" -type f -perm -111 | head -n 1)"
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Built binary not found: $BINARY_PATH" >&2
  exit 1
fi

if [[ "$OUTPUT_DIR" = /* ]]; then
  FINAL_OUTPUT_DIR="$OUTPUT_DIR"
else
  FINAL_OUTPUT_DIR="$PACKAGE_ROOT/$OUTPUT_DIR"
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/FilelayBuild.XXXXXX")"
APP_ROOT="$STAGING_DIR/$APP_NAME.app"
FINAL_APP_ROOT="$FINAL_OUTPUT_DIR/$APP_NAME.app"
FINAL_ZIP_PATH="$FINAL_OUTPUT_DIR/$APP_NAME.app.zip"
SAFE_EXPORT_DIR="${TMPDIR:-/tmp}/${APP_NAME}SignedExport"
SAFE_APP_ROOT="$SAFE_EXPORT_DIR/$APP_NAME.app"
SAFE_ZIP_PATH="$SAFE_EXPORT_DIR/$APP_NAME.app.zip"
CONTENTS_DIR="$APP_ROOT/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SCRIPTS_DIR="$RESOURCES_DIR/Scripts"

rm -rf "$APP_ROOT" "$FINAL_APP_ROOT" "$FINAL_ZIP_PATH"
mkdir -p "$MACOS_DIR" "$SCRIPTS_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp "$PACKAGE_ROOT/install_menu_app_autostart.sh" "$SCRIPTS_DIR/install_menu_app_autostart.sh"
cp "$PACKAGE_ROOT/uninstall_menu_app_autostart.sh" "$SCRIPTS_DIR/uninstall_menu_app_autostart.sh"
chmod +x "$SCRIPTS_DIR/install_menu_app_autostart.sh" "$SCRIPTS_DIR/uninstall_menu_app_autostart.sh"

sed \
  -e "s|__BUNDLE_IDENTIFIER__|$BUNDLE_ID|g" \
  -e "s|__APP_VERSION__|$APP_VERSION|g" \
  -e "s|__APP_BUILD__|$APP_BUILD|g" \
  "$PACKAGE_ROOT/AppBundle/Info.plist.template" > "$CONTENTS_DIR/Info.plist"

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if [[ "$SKIP_SIGN" -eq 0 ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(detect_sign_identity)"
  fi

  if [[ -n "$SIGN_IDENTITY" ]]; then
    xattr -cr "$APP_ROOT"
    codesign \
      --force \
      --deep \
      --timestamp \
      --options runtime \
      --sign "$SIGN_IDENTITY" \
      "$APP_ROOT"

    codesign --verify --deep --strict --verbose=2 "$APP_ROOT"
    rm -rf "$SAFE_APP_ROOT" "$SAFE_ZIP_PATH"
    mkdir -p "$SAFE_EXPORT_DIR"
    ditto "$APP_ROOT" "$SAFE_APP_ROOT"
    ditto -c -k --keepParent "$APP_ROOT" "$SAFE_ZIP_PATH"
    codesign --verify --deep --strict --verbose=2 "$SAFE_APP_ROOT"
  fi
fi

mkdir -p "$FINAL_OUTPUT_DIR"
ditto "$APP_ROOT" "$FINAL_APP_ROOT"
ditto -c -k --keepParent "$APP_ROOT" "$FINAL_ZIP_PATH"

if [[ "$SKIP_SIGN" -eq 0 && -n "$SIGN_IDENTITY" ]]; then
  if codesign --verify --deep --strict --verbose=2 "$FINAL_APP_ROOT" >/dev/null 2>&1; then
    FINAL_SIGNATURE_STATUS="valid"
  else
    SAFE_EXPORT_DIR="${TMPDIR:-/tmp}/${APP_NAME}SignedExport"
    SAFE_APP_ROOT="$SAFE_EXPORT_DIR/$APP_NAME.app"
    SAFE_ZIP_PATH="$SAFE_EXPORT_DIR/$APP_NAME.app.zip"
    rm -rf "$SAFE_APP_ROOT" "$SAFE_ZIP_PATH"
    mkdir -p "$SAFE_EXPORT_DIR"
    ditto "$APP_ROOT" "$SAFE_APP_ROOT"
    ditto -c -k --keepParent "$APP_ROOT" "$SAFE_ZIP_PATH"
    codesign --verify --deep --strict --verbose=2 "$SAFE_APP_ROOT"
    FINAL_SIGNATURE_STATUS="workspace_output_invalid"
  fi
fi

echo "Built app bundle:"
echo "  $FINAL_APP_ROOT"
echo "Built app archive:"
echo "  $FINAL_ZIP_PATH"
echo "Bundle ID: $BUNDLE_ID"
echo "Version: $APP_VERSION ($APP_BUILD)"
if [[ "$SKIP_SIGN" -eq 1 ]]; then
  echo "Signing: skipped"
elif [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing: $SIGN_IDENTITY"
else
  echo "Signing: no Developer ID Application identity found, app is unsigned"
fi

if [[ "$SKIP_SIGN" -eq 0 && -n "$SIGN_IDENTITY" ]]; then
  echo "Clean signed app bundle:"
  echo "  $SAFE_APP_ROOT"
  echo "Clean signed app archive:"
  echo "  $SAFE_ZIP_PATH"
fi

if [[ "$FINAL_SIGNATURE_STATUS" = "valid" ]]; then
  echo "Export verification: final output is signed and valid"
elif [[ "$FINAL_SIGNATURE_STATUS" = "workspace_output_invalid" ]]; then
  echo "Export verification: final output directory added macOS metadata that invalidates strict signature checks"
fi
