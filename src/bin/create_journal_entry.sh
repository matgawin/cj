#!/bin/bash

set -e

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Creates a daily journal entry from a template"
  echo
  echo "Options:"
  echo "  -t, --template FILE      Template file (default: embedded template)"
  echo "  -o, --output FILE        Output file (default: journal.daily.YYYY.MM.DD.md)"
  echo "  -e, --edit               Open the journal entry in editor after creation"
  echo "  -E, --editor EDITOR      Specify editor to use (default: $EDITOR)"
  echo "  -d, --directory DIR      Directory to save the journal entry (default: current directory)"
  echo "  -f, --force              Force overwrite without confirmation"
  echo "  -q, --quiet              Will not display any prompts, no messages"
  echo "  -i, --install-service    Install timestamp monitor as a systemd user service"
  echo "  -u, --uninstall-service  Uninstall timestamp monitor systemd user service"
  echo "  -h, --help               Display this help message and exit"
  echo
}

# Default embedded template
DEFAULT_TEMPLATE=$(
  cat <<'EOT'
---
id: {{ UNIQUE_ID }}
title: 'Day {{ DAY_COUNT }} -'
desc: ''
updated: {{ CURRENT_DATE }}
created: {{ CURRENT_DATE }}
---

## Feelings


## Thoughts
### General:


---
## Revision:
### Monthly:
[[journal.daily.{{ CURRENT_YEAR }}.{{ PREV_MONTH }}.{{ CURRENT_DAY }}.md]].


### Yearly:
[[journal.daily.{{ PREV_YEAR }}.{{ CURRENT_MONTH }}.{{ CURRENT_DAY }}.md]].


##
EOT
)

TEMPLATE_FILE=""
EDITOR="${EDITOR:-vi}"
OPEN_EDITOR=false
OUTPUT_FILE=""
OUTPUT_DIR="."
FORCE=false
INSTALL_SERVICE=false
UNINSTALL_SERVICE=false
QUIET_FAIL=false

if [[ "$(uname)" == "Darwin" ]]; then
  SED_IN_PLACE=(-i "")
else
  SED_IN_PLACE=(-i)
fi

print() {
  if [[ "$QUIET_FAIL" == "false" ]]; then
    echo "$1"
  fi
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -t | --template)
    TEMPLATE_FILE="$2"
    shift
    ;;
  -o | --output)
    OUTPUT_FILE="$2"
    shift
    ;;
  -e | --edit)
    OPEN_EDITOR=true
    ;;
  -E | --editor)
    EDITOR="$2"
    OPEN_EDITOR=true
    shift
    ;;
  -d | --directory)
    OUTPUT_DIR="$2"
    shift
    ;;
  -f | --force)
    FORCE=true
    ;;
  -q | --quiet)
    QUIET_FAIL=true
    ;;
  -i | --install-service)
    INSTALL_SERVICE=true
    ;;
  -u | --uninstall-service)
    UNINSTALL_SERVICE=true
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    print "Unknown parameter: $1"
    usage
    exit 1
    ;;
  esac
  shift
done

# Get script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [[ "${SCRIPT_DIR}" == *".local/bin" ]]; then
  PROJECT_ROOT="${SCRIPT_DIR}"
  MONITOR_SCRIPT="${SCRIPT_DIR}/journal-timestamp-monitor"
else
  PROJECT_ROOT="$(cd "$(dirname "${SCRIPT_DIR}")" &>/dev/null && pwd)"
  PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
  MONITOR_SCRIPT="${SCRIPT_DIR}/journal_timestamp_monitor.sh"
fi

if [[ "$INSTALL_SERVICE" = true ]]; then
  print "Installing journal timestamp monitor service..."

  SYSTEMD_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_DIR"

  cat > "$SYSTEMD_DIR/journal-timestamp-monitor.service" << EOF
[Unit]
Description=Journal Timestamp Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=${MONITOR_SCRIPT} "${OUTPUT_DIR}"
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable journal-timestamp-monitor.service
  systemctl --user start journal-timestamp-monitor.service

  print "Journal timestamp monitor service installed and started successfully!"
  print "You can check its status with: systemctl --user status journal-timestamp-monitor.service"
  exit 0
fi

if [[ "$UNINSTALL_SERVICE" = true ]]; then
  print "Uninstalling journal timestamp monitor service..."

  systemctl --user stop journal-timestamp-monitor.service 2>/dev/null || true
  systemctl --user disable journal-timestamp-monitor.service 2>/dev/null || true

  SYSTEMD_DIR="$HOME/.config/systemd/user"
  if [ -f "$SYSTEMD_DIR/journal-timestamp-monitor.service" ]; then
    rm "$SYSTEMD_DIR/journal-timestamp-monitor.service"
    systemctl --user daemon-reload
    print "Journal timestamp monitor service uninstalled successfully!"
  else
    print "Service file not found. It may have already been uninstalled."
  fi
  exit 0
fi

CURRENT_DATE=$(date +"%Y-%m-%d, %H:%M:%S")
CURRENT_YEAR=$(date +"%Y")
CURRENT_MONTH=$(date +"%m")
CURRENT_DAY=$(date +"%d")

START_DATE="2022-10-21"
if [[ "$(uname)" == "Darwin" ]]; then
  CURRENT_SECONDS=$(date -j -f "%Y-%m-%d" "$(date +%Y-%m-%d)" +%s)
  START_SECONDS=$(date -j -f "%Y-%m-%d" "$START_DATE" +%s)
else
  CURRENT_SECONDS=$(date -d "$(date +%Y-%m-%d)" +%s)
  START_SECONDS=$(date -d "$START_DATE" +%s)
fi
DAY_COUNT=$(((CURRENT_SECONDS - START_SECONDS) / 86400 + 1))

# Calculate previous month for monthly revision
PREV_MONTH_DATE=$(date -d "$CURRENT_YEAR-$CURRENT_MONTH-01 -1 month" "+%m" 2>/dev/null ||
  date -v-1m -j -f "%Y-%m-%d" "$CURRENT_YEAR-$CURRENT_MONTH-01" "+%m" 2>/dev/null)
PREV_YEAR=$((CURRENT_YEAR - 1))

# Define output filename if not specified
if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="journal.daily.${CURRENT_YEAR}.${CURRENT_MONTH}.${CURRENT_DAY}.md"
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/$OUTPUT_FILE"

if [[ -f "$OUTPUT_FILE" && "$FORCE" == "false" ]]; then
  print "Warning: Journal entry already exists: $OUTPUT_FILE"
  if [[ "$QUIET_FAIL" == "true" ]]; then
    exit 0
  fi
  read -r -p "Do you want to overwrite it? (y/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print "Operation cancelled"
    exit 0
  fi
  cp "$OUTPUT_FILE" "${OUTPUT_FILE}.bak"
  print "Backup created: ${OUTPUT_FILE}.bak"
fi

print "Creating journal entry: $OUTPUT_FILE"

# Generate unique ID (21 char alphanumeric string)
UNIQUE_ID=$(tr -dc 'a-z0-9' </dev/urandom | head -c 21)

TEMPLATE=$DEFAULT_TEMPLATE
if [[ -n "$TEMPLATE_FILE" ]]; then
  if [[ ! -f "$TEMPLATE_FILE" ]]; then
    print "Error: Template file '$TEMPLATE_FILE' not found"
    exit 1
  fi

  TEMPLATE=$(cat "$TEMPLATE_FILE")
fi

echo "$TEMPLATE" | sed -e "s/{{ CURRENT_YEAR }}/$CURRENT_YEAR/g" \
  -e "s/{{ CURRENT_MONTH }}/$CURRENT_MONTH/g" \
  -e "s/{{ CURRENT_DAY }}/$CURRENT_DAY/g" \
  -e "s/{{ CURRENT_DATE }}/$CURRENT_DATE/g" \
  -e "s/{{ DAY_COUNT }}/$DAY_COUNT/g" \
  -e "s/{{ UNIQUE_ID }}/$UNIQUE_ID/g" \
  >"$OUTPUT_FILE"

sed "${SED_IN_PLACE[@]}" \
  -e "s/{{ PREV_MONTH }}/$PREV_MONTH_DATE/g" \
  -e "s/{{ PREV_YEAR }}/$PREV_YEAR/g" \
  "$OUTPUT_FILE"

print "Journal entry created successfully!"

if [[ "$OPEN_EDITOR" = true ]]; then
  if command -v "$EDITOR" >/dev/null 2>&1; then
    print "Opening journal entry in $EDITOR..."
    "$EDITOR" "$OUTPUT_FILE"
  else
    print "Error: Editor '$EDITOR' not found, cannot open journal entry"
    exit 1
  fi
fi

exit 0