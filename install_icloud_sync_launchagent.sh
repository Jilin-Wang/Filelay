#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./install_icloud_sync_launchagent.sh --source <source_file> --dest <icloud_target_file> [--label <launchd_label>] [--interval <seconds>] [--verbose]

Description:
  Install and start a per-user launchd agent that runs icloud_file_sync.sh continuously.
  The agent starts at login and auto-restarts if it exits.

Defaults:
  --label    com.filelay.icloud-file-sync
  --interval 1

Notes:
  - Destination must be inside iCloud Drive root:
    ~/Library/Mobile Documents/com~apple~CloudDocs/
  - Destination parent folder must already exist.
USAGE
}

expand_tilde() {
  local p="$1"
  if [[ "$p" == ~* ]]; then
    printf '%s\n' "${p/#\~/$HOME}"
  else
    printf '%s\n' "$p"
  fi
}

SOURCE=""
DEST=""
LABEL="com.filelay.icloud-file-sync"
INTERVAL=1
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE="${2:-}"
      shift 2
      ;;
    --dest)
      DEST="${2:-}"
      shift 2
      ;;
    --label)
      LABEL="${2:-}"
      shift 2
      ;;
    --interval)
      INTERVAL="${2:-}"
      shift 2
      ;;
    --verbose)
      VERBOSE=1
      shift
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

if [[ -z "$SOURCE" || -z "$DEST" ]]; then
  echo "Error: --source and --dest are required." >&2
  usage >&2
  exit 1
fi

SOURCE="$(expand_tilde "$SOURCE")"
DEST="$(expand_tilde "$DEST")"

if [[ ! -f "$SOURCE" ]]; then
  echo "Error: source file does not exist or is not a regular file: $SOURCE" >&2
  exit 1
fi

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
  echo "Error: --interval must be an integer >= 1" >&2
  exit 1
fi

ICLOUD_ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
case "$DEST" in
  "$ICLOUD_ROOT"/*) ;;
  *)
    echo "Error: destination must be inside iCloud Drive root: $ICLOUD_ROOT" >&2
    exit 1
    ;;
esac

DEST_DIR="$(dirname "$DEST")"
if [[ ! -d "$DEST_DIR" ]]; then
  echo "Error: destination parent directory does not exist: $DEST_DIR" >&2
  echo "Please create it first." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/icloud_file_sync.sh"

if [[ ! -x "$SYNC_SCRIPT" ]]; then
  echo "Error: sync script not found or not executable: $SYNC_SCRIPT" >&2
  exit 1
fi

PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"

mkdir -p "$PLIST_DIR"

ARGS_XML="\n    <string>$SYNC_SCRIPT</string>\n    <string>--source</string>\n    <string>$SOURCE</string>\n    <string>--dest</string>\n    <string>$DEST</string>\n    <string>--interval</string>\n    <string>$INTERVAL</string>"
if [[ "$VERBOSE" -eq 1 ]]; then
  ARGS_XML+="\n    <string>--verbose</string>"
fi

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>

  <key>ProgramArguments</key>
  <array>$ARGS_XML
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST_PATH"
launchctl enable "gui/$UID/$LABEL"
launchctl kickstart -k "gui/$UID/$LABEL"

echo "Installed and started: $LABEL"
echo "Plist: $PLIST_PATH"
echo "Check status: launchctl print gui/$UID/$LABEL"
