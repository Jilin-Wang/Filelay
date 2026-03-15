#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"

backup_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    mv "$path" "${path}.bak.${TS}"
    echo "Backed up: $path -> ${path}.bak.${TS}"
  fi
}

backup_if_exists "$ROOT_DIR/.swiftpm"
backup_if_exists "$ROOT_DIR/.build"

echo "Local package state reset complete."
echo ""
echo "Next steps:"
echo "1) Close Xcode if open"
echo "2) Open package entry: open -a Xcode \"$ROOT_DIR/Package.swift\""
echo "3) Product -> Clean Build Folder"

echo ""
echo "If error persists, run this once to clear DerivedData for this project:"
echo "rm -rf ~/Library/Developer/Xcode/DerivedData/Filelay-*"
