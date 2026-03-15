#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./icloud_file_sync.sh --source <source_file> --dest <icloud_target_file> [--interval <seconds>] [--verbose]

Description:
  Watches one local source file and copies it to one iCloud target file whenever the source changes.
  If target exists, it is overwritten.

Safety:
  - Only the exact --source and --dest files are touched.
  - --dest must be under: ~/Library/Mobile Documents/com~apple~CloudDocs/
  - The destination parent directory must already exist.

Examples:
  ./icloud_file_sync.sh \
    --source "/Users/alex/Documents/report.md" \
    --dest "/Users/alex/Library/Mobile Documents/com~apple~CloudDocs/Sync/report.md"
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

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

SOURCE=""
DEST=""
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
  echo "Please create it manually to keep operations explicit and scoped." >&2
  exit 1
fi

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
  echo "Error: --interval must be an integer >= 1" >&2
  exit 1
fi

sync_once() {
  if [[ ! -f "$SOURCE" ]]; then
    if [[ "$VERBOSE" -eq 1 ]]; then
      echo "[$(timestamp)] Source missing, skip: $SOURCE" >&2
    fi
    return 0
  fi

  if [[ -f "$DEST" ]] && cmp -s "$SOURCE" "$DEST"; then
    return 0
  fi

  cp -f "$SOURCE" "$DEST"
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "[$(timestamp)] Synced: $SOURCE -> $DEST"
  fi
}

watch_with_fswatch() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "[$(timestamp)] Watch mode: fswatch"
  fi
  sync_once

  while true; do
    fswatch -1 "$SOURCE" >/dev/null 2>&1 || true
    sync_once
  done
}

watch_with_polling() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "[$(timestamp)] Watch mode: polling every ${INTERVAL}s (fswatch not found)"
  fi
  sync_once

  local last_mtime
  last_mtime="$(stat -f '%m' "$SOURCE" 2>/dev/null || echo 0)"

  while true; do
    sleep "$INTERVAL"

    local current_mtime
    current_mtime="$(stat -f '%m' "$SOURCE" 2>/dev/null || echo 0)"

    if [[ "$current_mtime" != "$last_mtime" ]]; then
      last_mtime="$current_mtime"
      sync_once
    fi
  done
}

if [[ "$VERBOSE" -eq 1 ]]; then
  trap 'echo "[$(timestamp)] Stopped"; exit 0' INT TERM
else
  trap 'exit 0' INT TERM
fi

if command -v fswatch >/dev/null 2>&1; then
  watch_with_fswatch
else
  watch_with_polling
fi
