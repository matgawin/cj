#!/bin/bash
set -e

log_init() {
  if [[ "$QUIET_FAIL" == "false" ]]; then
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[${timestamp}] [${level}] ${message}" >> "/tmp/journal.log"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [[ "${SCRIPT_DIR}" == *".local/bin" ]]; then
  COMMON_LIB="${HOME}/.local/share/journal/common.sh"
  if [[ ! -f "${COMMON_LIB}" ]]; then
    mkdir -p "$(dirname "${COMMON_LIB}")"
    if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
      cp "${SCRIPT_DIR}/../lib/common.sh" "${COMMON_LIB}"
    fi
  fi
else
  COMMON_LIB="${SCRIPT_DIR}/../lib/common.sh"
fi

if [[ -f "${COMMON_LIB}" ]]; then
  # shellcheck disable=SC1090
  source "${COMMON_LIB}"
else
  error_exit() {
    echo "Error: $1" >&2
    exit "${2:-1}"
  }
fi

JOURNAL_LOG_LEVEL="INFO"

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Creates a daily journal entry from a template"
  echo
  echo "Options:"
  echo "  -t, --template FILE        Template file (default: embedded template)"
  echo "  -o, --output FILE          Output file (default: journal.daily.YYYY.MM.DD.md)"
  echo "  -e, --edit                 Open the journal entry in editor after creation"
  echo "  -E, --editor EDITOR        Specify editor to use (default: $EDITOR)"
  echo "  -d, --directory DIR        Directory to save the journal entry (default: current directory)"
  echo "  -f, --force                Force overwrite without confirmation"
  echo "  -q, --quiet                Will not display any prompts, no messages"
  echo "  -i, --install-service      Install timestamp monitor as a systemd user service"
  echo "  -u, --uninstall-service    Uninstall timestamp monitor systemd user service"
  echo "  -s, --set-start-date DATE  Set the start date for journal entries (default: $(date +"%Y-%m-%d"))"
  echo "      --date DATE            Override the date for this journal entry (default: today)"
  echo "  -h, --help                 Display this help message and exit"
  echo
}

DEFAULT_TEMPLATE="---
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


###"

config_dir="${HOME}/.config/cj"
config_start_date="${config_dir}/start_date"

TEMPLATE_FILE=""
EDITOR="${EDITOR:-vi}"
OPEN_EDITOR=false
OUTPUT_FILE=""
OUTPUT_DIR="."
FORCE=false
INSTALL_SERVICE=false
UNINSTALL_SERVICE=false
QUIET_FAIL=false
OVERRIDE_DATE=""

if [[ "$(uname)" == "Darwin" ]]; then
  SED_IN_PLACE=(-i "")
else
  SED_IN_PLACE=(-i)
fi

print() {
  local message="$1"
  local level="${2:-INFO}"

  if type -t log >/dev/null; then
    log "$level" "$message"
  else
    log_init "$level" "$message"
  fi

  if [[ "$QUIET_FAIL" == "false" ]]; then
    case "$level" in
      "ERROR")
        echo "Error: $message" >&2
        ;;
      "WARN")
        echo "Warning: $message" >&2
        ;;
      *)
        echo "$message"
        ;;
    esac
  fi
}

validate_args() {
  local arg="$1"
  local value="$2"
  local requires_value=true

  case "$arg" in
    -t|--template|-o|--output|-E|--editor|-d|--directory|-s|--set-start-date|--date)
      if [[ -z "$value" || "$value" == -* ]]; then
        print "Option $arg requires a value" "ERROR"
        usage
        exit 1
      fi

      case "$arg" in
        -t|--template)
          if [[ -n "$value" && ! -f "$value" && "$value" != /* ]]; then
            if [[ ! -f "$(pwd)/$value" ]]; then
              print "Template file not found: $value" "WARN"
            fi
          fi
          ;;
        -d|--directory)
          if [[ ! "$value" =~ ^[a-zA-Z0-9./_-]+$ ]]; then
            print "Directory path contains invalid characters: $value" "ERROR"
            exit 1
          fi
          ;;
        -E|--editor)
          if ! command -v "$value" >/dev/null 2>&1; then
            print "Editor not found in PATH: $value" "WARN"
          fi
          ;;
        --date)
          if ! date -d "$value" >/dev/null 2>&1 && ! date -j -f "%Y-%m-%d" "$value" >/dev/null 2>&1; then
            print "Invalid date format: $value (expected YYYY-MM-DD)" "ERROR"
            exit 1
          fi
          ;;
      esac
      ;;
    -e|--edit|-f|--force|-q|--quiet|-i|--install-service|-u|--uninstall-service|-h|--help)
      requires_value=false
      ;;
    *)
      print "Unknown parameter: $arg" "ERROR"
      usage
      exit 1
      ;;
  esac

  return 0
}

setStartDate() {
  local start_date="$1"

  if [[ ! -n "$start_date" ]]; then
    return
  fi

  if ! date -d "$start_date" >/dev/null 2>&1 && ! date -j -f "%Y-%m-%d" "$start_date" >/dev/null 2>&1; then
    print "Invalid date format: $start_date (expected YYYY-MM-DD)" "ERROR"
    exit 1
  fi

  mkdir -p "$config_dir"
  echo "$start_date" > "$config_start_date"
  print "Start date set to: $start_date" "INFO" >&2
  return 0
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -t | --template)
    if [[ -z "$2" || "$2" == -* ]]; then
      print "Option $1 requires a value" "ERROR"
      usage
      exit 1
    fi
    validate_args "$1" "$2"
    TEMPLATE_FILE="$2"
    shift
    ;;
  -o | --output)
    if [[ -z "$2" || "$2" == -* ]]; then
      print "Option $1 requires a value" "ERROR"
      usage
      exit 1
    fi
    validate_args "$1" "$2"
    OUTPUT_FILE="$2"
    shift
    ;;
  -e | --edit)
    validate_args "$1" ""
    OPEN_EDITOR=true
    ;;
  -E | --editor)
    if [[ -z "$2" || "$2" == -* ]]; then
      print "Option $1 requires a value" "ERROR"
      usage
      exit 1
    fi
    validate_args "$1" "$2"
    EDITOR="$2"
    OPEN_EDITOR=true
    shift
    ;;
  -d | --directory)
    if [[ -z "$2" || "$2" == -* ]]; then
      print "Option $1 requires a value" "ERROR"
      usage
      exit 1
    fi
    validate_args "$1" "$2"
    OUTPUT_DIR="$2"
    shift
    ;;
  -f | --force)
    validate_args "$1" ""
    FORCE=true
    ;;
  -q | --quiet)
    validate_args "$1" ""
    QUIET_FAIL=true
    ;;
  -i | --install-service)
    validate_args "$1" ""
    INSTALL_SERVICE=true
    ;;
  -u | --uninstall-service)
    validate_args "$1" ""
    UNINSTALL_SERVICE=true
    ;;
  -s | --set-start-date)
    if [[ -z "$2" || "$2" == -* ]]; then
      print "Option $1 requires a value" "ERROR"
      usage
      exit 1
    fi
    validate_args "$1" "$2"
    setStartDate "$2"
    shift
    ;;
  --date)
    if [[ -z "$2" || "$2" == -* ]]; then
      print "Option $1 requires a value" "ERROR"
      usage
      exit 1
    fi
    validate_args "$1" "$2"
    OVERRIDE_DATE="$2"
    shift
    ;;
  -h | --help)
    validate_args "$1" ""
    usage
    exit 0
    ;;
  *)
    print "Unknown parameter: $1" "ERROR"
    usage
    exit 1
    ;;
  esac
  shift
done

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

# Use override date if provided, otherwise use current date
if [[ -n "$OVERRIDE_DATE" ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    CURRENT_DATE=$(date -j -f "%Y-%m-%d" "$OVERRIDE_DATE" +"%Y-%m-%d, %H:%M:%S")
    CURRENT_YEAR=$(date -j -f "%Y-%m-%d" "$OVERRIDE_DATE" +"%Y")
    CURRENT_MONTH=$(date -j -f "%Y-%m-%d" "$OVERRIDE_DATE" +"%m")
    CURRENT_DAY=$(date -j -f "%Y-%m-%d" "$OVERRIDE_DATE" +"%d")
  else
    CURRENT_DATE=$(date -d "$OVERRIDE_DATE" +"%Y-%m-%d, %H:%M:%S")
    CURRENT_YEAR=$(date -d "$OVERRIDE_DATE" +"%Y")
    CURRENT_MONTH=$(date -d "$OVERRIDE_DATE" +"%m")
    CURRENT_DAY=$(date -d "$OVERRIDE_DATE" +"%d")
  fi
else
  CURRENT_DATE=$(date +"%Y-%m-%d, %H:%M:%S")
  CURRENT_YEAR=$(date +"%Y")
  CURRENT_MONTH=$(date +"%m")
  CURRENT_DAY=$(date +"%d")
fi

get_start_date() {
  if [[ -f "$config_start_date" ]]; then
    cat "$config_start_date"
  else
    local default_date
    default_date=$(date +"%Y-%m-%d")

    if [[ "$QUIET_FAIL" == "false" ]]; then
      print "First time setup: Setting start date for day counting" "INFO" >&2
      read -r -p "Enter start date (YYYY-MM-DD) or press Enter for today [$default_date]: " user_date
      if [[ -n "$user_date" ]]; then
        if ! date -d "$user_date" >/dev/null 2>&1 && ! date -j -f "%Y-%m-%d" "$user_date" >/dev/null 2>&1; then
          print "Invalid date format, using today: $default_date" "WARN" >&2
          user_date="$default_date"
        fi
      else
        user_date="$default_date"
      fi
    else
      user_date="$default_date"
    fi

    setStartDate "$user_date"
    echo "$user_date"
  fi
}

START_DATE=$(get_start_date)
# Use override date or current date for day count calculation
TARGET_DATE_FOR_COUNT="${OVERRIDE_DATE:-$(date +%Y-%m-%d)}"
if [[ "$(uname)" == "Darwin" ]]; then
  CURRENT_SECONDS=$(date -j -f "%Y-%m-%d" "$TARGET_DATE_FOR_COUNT" +%s)
  START_SECONDS=$(date -j -f "%Y-%m-%d" "$START_DATE" +%s)
else
  CURRENT_SECONDS=$(date -d "$TARGET_DATE_FOR_COUNT" +%s)
  START_SECONDS=$(date -d "$START_DATE" +%s)
fi
DAY_COUNT=$(((CURRENT_SECONDS - START_SECONDS) / 86400 + 1))

PREV_MONTH_DATE=$(date -d "$CURRENT_YEAR-$CURRENT_MONTH-01 -1 month" "+%m" 2>/dev/null ||
  date -v-1m -j -f "%Y-%m-%d" "$CURRENT_YEAR-$CURRENT_MONTH-01" "+%m" 2>/dev/null)
PREV_YEAR=$((CURRENT_YEAR - 1))

if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="journal.daily.${CURRENT_YEAR}.${CURRENT_MONTH}.${CURRENT_DAY}.md"
fi

if [[ ! -d "$OUTPUT_DIR" ]]; then
  print "Output directory does not exist: $OUTPUT_DIR" "INFO"

  if ! mkdir -p "$OUTPUT_DIR" 2>/dev/null; then
    print "Failed to create output directory: $OUTPUT_DIR" "ERROR"
    exit 1
  fi

  print "Created output directory: $OUTPUT_DIR" "INFO"
else
  if [[ ! -w "$OUTPUT_DIR" ]]; then
    print "Output directory is not writable: $OUTPUT_DIR" "ERROR"
    exit 1
  fi
fi

OUTPUT_FILE="$OUTPUT_DIR/$OUTPUT_FILE"

if [[ -f "$OUTPUT_FILE" ]]; then
  if [[ "$FORCE" == "false" ]]; then
    print "Warning: Journal entry already exists: $OUTPUT_FILE" "WARN"

    if [[ ! -w "$OUTPUT_FILE" ]]; then
      print "Existing journal entry is not writable: $OUTPUT_FILE" "ERROR"
      exit 1
    fi

    if [[ "$QUIET_FAIL" == "true" ]]; then
      exit 0
    fi

    read -r -p "Do you want to overwrite it? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
      print "Operation cancelled" "INFO"
      exit 0
    fi

    if ! cp "$OUTPUT_FILE" "${OUTPUT_FILE}.bak" 2>/dev/null; then
      print "Failed to create backup file: ${OUTPUT_FILE}.bak" "WARN"
    else
      print "Backup created: ${OUTPUT_FILE}.bak" "INFO"
    fi
  else
    print "Overwriting existing journal entry (forced): $OUTPUT_FILE" "INFO"

    if [[ ! -w "$OUTPUT_FILE" ]]; then
      print "Existing journal entry is not writable: $OUTPUT_FILE" "ERROR"
      exit 1
    fi
  fi
elif [[ -e "$OUTPUT_FILE" ]]; then
  print "Output path exists but is not a regular file: $OUTPUT_FILE" "ERROR"
  exit 1
fi

print "Creating journal entry: $OUTPUT_FILE"

# Generate unique ID (21 char alphanumeric string)
UNIQUE_ID=$(tr -dc 'a-z0-9' </dev/urandom | head -c 21)

TEMPLATE=$DEFAULT_TEMPLATE
if [[ -n "$TEMPLATE_FILE" ]]; then
  if [[ ! -f "$TEMPLATE_FILE" ]]; then
    print "Error: Template file '$TEMPLATE_FILE' not found" "ERROR"
    exit 1
  fi

  if [[ ! -r "$TEMPLATE_FILE" ]]; then
    print "Error: Template file '$TEMPLATE_FILE' is not readable" "ERROR"
    exit 1
  fi

  if ! TEMPLATE=$(cat "$TEMPLATE_FILE" 2>/dev/null); then
    print "Error: Failed to read template file '$TEMPLATE_FILE'" "ERROR"
    exit 1
  fi

  if [[ ! "$TEMPLATE" == *"---"* ]]; then
    print "Warning: Template file does not contain YAML frontmatter markers (---)" "WARN"
  fi

  if [[ ! "$TEMPLATE" == *"{{CURRENT_DATE}}"* && ! "$TEMPLATE" == *"{{ CURRENT_DATE }}"* ]]; then
    print "Warning: Template does not contain {{ CURRENT_DATE }} placeholder" "WARN"
  fi

  print "Using custom template: $TEMPLATE_FILE" "INFO"
fi

print "Processing template..." "DEBUG"

TEMP_FILE="$(mktemp)"

if ! echo "$TEMPLATE" | sed -e "s/{{ CURRENT_YEAR }}/$CURRENT_YEAR/g" \
  -e "s/{{ CURRENT_MONTH }}/$CURRENT_MONTH/g" \
  -e "s/{{ CURRENT_DAY }}/$CURRENT_DAY/g" \
  -e "s/{{ CURRENT_DATE }}/$CURRENT_DATE/g" \
  -e "s/{{ DAY_COUNT }}/$DAY_COUNT/g" \
  -e "s/{{ UNIQUE_ID }}/$UNIQUE_ID/g" \
  >"$TEMP_FILE" 2>/dev/null; then

  print "Error: Failed to process template (phase 1)" "ERROR"
  rm -f "$TEMP_FILE" 2>/dev/null
  exit 1
fi

if [[ ! -f "$TEMP_FILE" || ! -s "$TEMP_FILE" ]]; then
  print "Error: Failed to create processed template file" "ERROR"
  rm -f "$TEMP_FILE" 2>/dev/null
  exit 1
fi

if ! sed "${SED_IN_PLACE[@]}" \
  -e "s/{{ PREV_MONTH }}/$PREV_MONTH_DATE/g" \
  -e "s/{{ PREV_YEAR }}/$PREV_YEAR/g" \
  "$TEMP_FILE" 2>/dev/null; then

  print "Error: Failed to process template (phase 2)" "ERROR"
  rm -f "$TEMP_FILE" 2>/dev/null
  exit 1
fi

if ! mv "$TEMP_FILE" "$OUTPUT_FILE" 2>/dev/null; then
  print "Error: Failed to write journal entry to: $OUTPUT_FILE" "ERROR"
  rm -f "$TEMP_FILE" 2>/dev/null
  exit 1
fi

print "Journal entry created successfully!" "INFO"

if [[ "$OPEN_EDITOR" = true ]]; then
  if ! command -v "$EDITOR" >/dev/null 2>&1; then
    print "Error: Editor '$EDITOR' not found, cannot open journal entry" "ERROR"
    print "You can still find your journal entry at: $OUTPUT_FILE" "INFO"
    exit 1
  fi

  if [[ ! -f "$OUTPUT_FILE" ]]; then
    print "Error: Journal entry file no longer exists: $OUTPUT_FILE" "ERROR"
    exit 1
  fi

  if [[ ! -r "$OUTPUT_FILE" ]]; then
    print "Error: Journal entry is not readable: $OUTPUT_FILE" "ERROR"
    exit 1
  fi

  print "Opening journal entry in $EDITOR..." "INFO"

  if ! "$EDITOR" "$OUTPUT_FILE"; then
    print "Warning: Editor '$EDITOR' exited with an error" "WARN"
    print "Your journal entry was created successfully at: $OUTPUT_FILE" "INFO"
    exit 1
  fi
fi

exit 0