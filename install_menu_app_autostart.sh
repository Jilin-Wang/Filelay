#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./install_menu_app_autostart.sh --app "/Applications/Filelay.app" [--label com.filelay.menubar]

Description:
  Register a macOS LaunchAgent for the menu bar app so it starts at login.
USAGE
}

APP_PATH=""
LABEL="com.filelay.menubar"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --label)
      LABEL="${2:-}"
      shift 2
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

if [[ -z "$APP_PATH" ]]; then
  echo "Error: --app is required" >&2
  usage >&2
  exit 1
fi

if [[ "$APP_PATH" == ~* ]]; then
  APP_PATH="${APP_PATH/#\~/$HOME}"
fi

APP_BIN="$APP_PATH/Contents/MacOS/Filelay"
if [[ ! -x "$APP_BIN" ]]; then
  echo "Error: app binary not found or not executable: $APP_BIN" >&2
  exit 1
fi

PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
mkdir -p "$PLIST_DIR"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>

  <key>ProgramArguments</key>
  <array>
    <string>$APP_BIN</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST_PATH"
launchctl enable "gui/$UID/$LABEL"

echo "Installed login item: $LABEL"
echo "Plist: $PLIST_PATH"
echo "Check: launchctl print gui/$UID/$LABEL"
