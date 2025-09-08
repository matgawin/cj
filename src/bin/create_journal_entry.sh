#!/usr/bin/env bash
#
# create_journal_entry.sh - Daily journal entry creation and management tool
#
# This script creates daily journal entries from templates with automatic timestamp
# management, SOPS encryption support, and systemd service integration. It provides
# a comprehensive solution for maintaining encrypted or unencrypted journal files.
#
# Features:
#   - Template-based journal entry creation with variable substitution
#   - SOPS encryption support for secure journal storage
#   - Systemd service installation for automated timestamp monitoring
#   - Migration tool for converting existing entries to encrypted format
#   - Comprehensive error handling and validation
#   - Interactive and quiet operation modes
#
# Functions:
#   - log_init()              Initialize logging for fallback scenarios
#   - usage()                 Display comprehensive help information
#   - print()                 Enhanced logging and output with level filtering
#   - validate_args()         Validate command-line arguments and options
#   - setStartDate()          Set the start date for day counting
#   - get_start_date()        Get or initialize the start date configuration
#   - migrate_to_encrypted()  Convert existing journal entries to encrypted format
#
# Usage: create_journal_entry.sh [OPTIONS]
#
# Environment Variables:
#   EDITOR               - Default text editor for opening entries
#   SOPS_CONFIG_PATH    - Custom SOPS configuration file path
#
set -e

#
# log_init() - Initialize basic logging functionality for fallback scenarios
#
# Usage: log_init <level> <message>
#
# Parameters:
#   level   - Log level (DEBUG, INFO, WARN, ERROR)
#   message - Message to log
#
# Behavior:
#   Only logs if QUIET_FAIL is false. Used when common.sh is not available.
#
# Returns:
#   Always returns 0
#
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

# Source error handling utilities
ERROR_LIB="${SCRIPT_DIR}/../lib/error_handling.sh"
if [[ "${SCRIPT_DIR}" == *".local/bin" ]]; then
  ERROR_LIB="${HOME}/.local/share/journal/error_handling.sh"
  if [[ ! -f "${ERROR_LIB}" ]]; then
    mkdir -p "$(dirname "${ERROR_LIB}")"
    if [[ -f "${SCRIPT_DIR}/../lib/error_handling.sh" ]]; then
      cp "${SCRIPT_DIR}/../lib/error_handling.sh" "${ERROR_LIB}"
    fi
  fi
fi

if [[ -f "${ERROR_LIB}" ]]; then
  # shellcheck disable=SC1090
  source "${ERROR_LIB}" 2>/dev/null
fi

# Source sops utilities if available
SOPS_LIB="${SCRIPT_DIR}/../lib/sops_utils.sh"
if [[ "${SCRIPT_DIR}" == *".local/bin" ]]; then
  SOPS_LIB="${HOME}/.local/share/journal/sops_utils.sh"
  if [[ ! -f "${SOPS_LIB}" ]]; then
    mkdir -p "$(dirname "${SOPS_LIB}")"
    if [[ -f "${SCRIPT_DIR}/../lib/sops_utils.sh" ]]; then
      cp "${SCRIPT_DIR}/../lib/sops_utils.sh" "${SOPS_LIB}"
    fi
  fi
fi

SOPS_AVAILABLE=false
if [[ -f "${SOPS_LIB}" ]]; then
  # shellcheck disable=SC1090
  source "${SOPS_LIB}" 2>/dev/null && SOPS_AVAILABLE=true
fi

JOURNAL_LOG_LEVEL="INFO"

#
# usage() - Display comprehensive help information and usage examples
#
# Prints detailed help information including all command-line options, SOPS encryption
# setup instructions, troubleshooting guidance, and usage examples.
#
# Usage: usage
#
# Returns:
#   Always returns 0
#
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
  echo "  -q, --quiet                Suppress informational messages (errors still shown)"
  echo "  -v, --verbose              Enable verbose output for debugging"
  echo "  -i, --install-service      Install timestamp monitor as a systemd user service"
  echo "  -u, --uninstall-service    Uninstall timestamp monitor systemd user service"
  echo "  -s, --set-start-date DATE  Set the start date for journal entries (default: $(date +"%Y-%m-%d"))"
  echo "      --date DATE            Override the date for this journal entry (default: today)"
  echo "      --sops-config FILE     Override default sops config location (.sops.yaml)"
  echo "      --migrate-to-encrypted Migration command to convert existing entries to encrypted format"
  echo "      --open FILE            Open an existing journal entry (automatically uses SOPS if encrypted)"
  echo "  -h, --help                 Display this help message and exit"
  echo
  echo "Encryption (SOPS) Support:"
  echo "  This tool supports automatic encryption using Mozilla SOPS."
  echo "  "
  echo "  Setup Steps:"
  echo "    1. Install SOPS: https://github.com/mozilla/sops"
  echo "    2. Set up encryption keys (Age, PGP, KMS, etc.)"
  echo "    3. Create .sops.yaml configuration file"
  echo "    4. New journal entries will be automatically encrypted"
  echo "  "
  echo "  Common SOPS Commands:"
  echo "    Create config:     sops --encrypt .sops.yaml"
  echo "    Edit encrypted:    sops <encrypted-file>"
  echo "    View encrypted:    sops --decrypt <encrypted-file>"
  echo "    Migrate existing:  $0 --migrate-to-encrypted"
  echo "  "
  echo "  Troubleshooting:"
  echo "    - Ensure SOPS is in PATH and keys are accessible"
  echo "    - Check .sops.yaml format and key configuration"
  echo "    - Use --verbose for detailed error information"
  echo "    - Test encryption with: sops --encrypt /dev/stdin <<< 'test: data'"
  echo
  echo "Examples:"
  echo "  $0                         # Create today's entry"
  echo "  $0 --date 2024-01-15       # Create entry for specific date"
  echo "  $0 -e                      # Create and open in editor"
  echo "  $0 --migrate-to-encrypted  # Convert existing entries to encrypted"
  echo "  $0 --open journal.daily.2024.01.15.md  # Open existing entry"
  echo "  $0 --verbose               # Show detailed processing information"
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


##"

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
VERBOSE_MODE=false
OVERRIDE_DATE=""
SOPS_CONFIG_PATH=""
MIGRATE_TO_ENCRYPTED=false
OPEN_FILE=""

if [[ "$(uname)" == "Darwin" ]]; then
  SED_IN_PLACE=(-i "")
else
  SED_IN_PLACE=(-i)
fi

#
# print() - Enhanced logging and output function with level-based filtering
#
# Usage: print <message> [level]
#
# Parameters:
#   message - Message to display/log
#   level   - Optional log level: INFO, ERROR, WARN, DEBUG (default: INFO)
#
# Behavior:
#   - Integrates with log() function if available
#   - Respects QUIET_FAIL and VERBOSE_MODE settings
#   - Filters output based on log level and mode settings
#   - Redirects ERROR/WARN to stderr, others to stdout
#
# Returns:
#   Always returns 0
#
print() {
  local message="$1"
  local level="${2:-INFO}"

  if type -t log >/dev/null; then
    log "$level" "$message"
  else
    log_init "$level" "$message"
  fi

  # Enhanced output handling with verbose mode
  local should_print=true

  # In quiet mode, only show errors
  if [[ "$QUIET_FAIL" == "true" && "$level" != "ERROR" ]]; then
    should_print=false
  fi

  # In verbose mode, show debug messages
  if [[ "$VERBOSE_MODE" == "true" || "$level" == "ERROR" || "$level" == "WARN" ]]; then
    should_print=true
  fi

  # In normal mode, filter debug messages unless verbose is enabled
  if [[ "$level" == "DEBUG" && "$VERBOSE_MODE" == "false" ]]; then
    should_print=false
  fi

  if [[ "$should_print" == "true" ]]; then
    case "$level" in
      "ERROR")
        echo "Error: $message" >&2
        ;;
      "WARN")
        echo "Warning: $message" >&2
        ;;
      "DEBUG")
        if [[ "$VERBOSE_MODE" == "true" ]]; then
          echo "Debug: $message" >&2
        fi
        ;;
      *)
        echo "$message"
        ;;
    esac
  fi
}

#
# validate_args() - Validate command-line arguments and their values
#
# Usage: validate_args <argument> <value>
#
# Parameters:
#   argument - Command-line argument to validate
#   value    - Value associated with the argument
#
# Behavior:
#   - Validates argument syntax and value requirements
#   - Performs type-specific validation (dates, files, directories)
#   - Calls exit_with_code on validation failures
#   - Provides helpful error messages for invalid inputs
#
# Returns:
#   0 on successful validation, exits on failure
#
validate_args() {
  local arg="$1"
  local value="$2"
  local requires_value=true

  case "$arg" in
    -t|--template|-o|--output|-E|--editor|-d|--directory|-s|--set-start-date|--date|--sops-config|--open)
      if [[ -z "$value" || "$value" == -* ]]; then
        print "Option $arg requires a value" "ERROR"
        usage
        exit_with_code "GENERAL" "Missing required argument for option: $arg"
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
            exit_with_code "GENERAL" "Directory path contains invalid characters: $value"
          fi
          ;;
        -E|--editor)
          if ! command -v "$value" >/dev/null 2>&1; then
            print "Editor not found in PATH: $value" "WARN"
          fi
          ;;
        --date)
          if ! date -d "$value" >/dev/null 2>&1 && ! date -j -f "%Y-%m-%d" "$value" >/dev/null 2>&1; then
            exit_with_code "GENERAL" "Invalid date format: $value (expected YYYY-MM-DD)"
          fi
          ;;
        --sops-config)
          if [[ ! -f "$value" ]]; then
            exit_with_code "CONFIG" "SOPS config file not found: $value"
          fi
          if [[ ! -r "$value" ]]; then
            exit_with_code "CONFIG" "SOPS config file is not readable: $value"
          fi
          ;;
        --open)
          if [[ ! -f "$value" ]]; then
            exit_with_code "GENERAL" "File to open not found: $value"
          fi
          if [[ ! -r "$value" ]]; then
            exit_with_code "GENERAL" "File to open is not readable: $value"
          fi
          ;;
      esac
      ;;
    -e|--edit|-f|--force|-q|--quiet|-v|--verbose|-i|--install-service|-u|--uninstall-service|--migrate-to-encrypted|-h|--help)
      requires_value=false
      ;;
    *)
      print "Unknown parameter: $arg" "ERROR"
      usage
      exit_with_code "GENERAL" "Unknown parameter: $arg"
      ;;
  esac

  return 0
}

#
# setStartDate() - Set the start date for day counting in journal entries
#
# Usage: setStartDate <start_date>
#
# Parameters:
#   start_date - Date in YYYY-MM-DD format to set as the start date
#
# Behavior:
#   - Validates date format using system date command
#   - Creates configuration directory if it doesn't exist
#   - Saves start date to configuration file
#   - Provides user feedback about the operation
#
# Returns:
#   0 on success, calls exit_with_code on invalid date format
#
setStartDate() {
  local start_date="$1"

  if [[ -z "$start_date" ]]; then
    return
  fi

  if ! date -d "$start_date" >/dev/null 2>&1 && ! date -j -f "%Y-%m-%d" "$start_date" >/dev/null 2>&1; then
    exit_with_code "GENERAL" "Invalid date format: $start_date (expected YYYY-MM-DD)"
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
  -v | --verbose)
    validate_args "$1" ""
    VERBOSE_MODE=true
    JOURNAL_LOG_LEVEL="DEBUG"
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
  --sops-config)
    if [[ -z "$2" || "$2" == -* ]]; then
      print "Option $1 requires a value" "ERROR"
      usage
      exit 1
    fi
    validate_args "$1" "$2"
    SOPS_CONFIG_PATH="$2"
    shift
    ;;
  --migrate-to-encrypted)
    validate_args "$1" ""
    MIGRATE_TO_ENCRYPTED=true
    ;;
  --open)
    if [[ -z "$2" || "$2" == -* ]]; then
      print "Option $1 requires a value" "ERROR"
      usage
      exit 1
    fi
    validate_args "$1" "$2"
    OPEN_FILE="$2"
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

  # Detect sops config for service environment
  service_sops_config=""
  service_environment_vars=""

  if [[ "$SOPS_AVAILABLE" == "true" ]]; then
    service_sops_config=$(detect_sops_config 2>/dev/null || echo "")
    if [[ -n "$service_sops_config" ]]; then
      # Make path absolute for service
      if [[ "$service_sops_config" != /* ]]; then
        service_sops_config="$(pwd)/$service_sops_config"
      fi
      print "Service will use SOPS config: $service_sops_config"
      service_environment_vars="Environment=SOPS_CONFIG_PATH=$service_sops_config"
    else
      print "No SOPS config detected - service will operate in unencrypted mode"
    fi
  fi

  # Make OUTPUT_DIR absolute for service
  service_working_dir="$OUTPUT_DIR"
  if [[ "$service_working_dir" != /* ]]; then
    service_working_dir="$(pwd)/$service_working_dir"
  fi

  cat > "$SYSTEMD_DIR/journal-timestamp-monitor.service" << EOF
[Unit]
Description=Journal Timestamp Monitor Service (with encryption support)
After=network.target graphical-session.target

[Service]
Type=simple
ExecStart=${MONITOR_SCRIPT} "${service_working_dir}"
Restart=on-failure
RestartSec=5s
WorkingDirectory=${service_working_dir}
${service_environment_vars}

[Install]
WantedBy=default.target
EOF

  # Install auto-creation service and timer if they don't exist
  if [[ ! -f "$SYSTEMD_DIR/journal-auto-create.service" ]]; then
    print "Installing journal auto-creation service..."

    # Use the main script for auto-creation
    main_script_path
    if [[ "${SCRIPT_DIR}" == *".local/bin" ]]; then
      main_script_path="${SCRIPT_DIR}/cj"
    else
      main_script_path="${SCRIPT_DIR}/create_journal_entry.sh"
    fi

    cat > "$SYSTEMD_DIR/journal-auto-create.service" << EOF
[Unit]
Description=Create Daily Journal Entry (with encryption support)

[Service]
Type=oneshot
ExecStart=${main_script_path} -d "${service_working_dir}" -q
WorkingDirectory=${service_working_dir}
${service_environment_vars}
EOF

    cat > "$SYSTEMD_DIR/journal-auto-create.timer" << EOF
[Unit]
Description=Daily Journal Entry Creation
Requires=journal-auto-create.service

[Timer]
OnCalendar=*-*-* 22:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    print "Auto-creation service and timer installed"
  fi

  systemctl --user daemon-reload
  systemctl --user enable journal-timestamp-monitor.service
  systemctl --user start journal-timestamp-monitor.service

  # Enable auto-creation timer if it was created
  if [[ -f "$SYSTEMD_DIR/journal-auto-create.timer" ]]; then
    systemctl --user enable journal-auto-create.timer
    systemctl --user start journal-auto-create.timer
    print "Auto-creation timer enabled"
  fi

  print "Journal services installed and started successfully!"
  print "Timestamp Monitor: systemctl --user status journal-timestamp-monitor.service"
  if [[ -f "$SYSTEMD_DIR/journal-auto-create.timer" ]]; then
    print "Auto-Creation Timer: systemctl --user status journal-auto-create.timer"
  fi
  exit 0
fi

if [[ "$UNINSTALL_SERVICE" = true ]]; then
  print "Uninstalling journal services..."

  SYSTEMD_DIR="$HOME/.config/systemd/user"
  services_removed=0

  # Stop and disable timestamp monitor service
  if systemctl --user stop journal-timestamp-monitor.service 2>/dev/null; then
    print "Stopped timestamp monitor service"
  fi
  if systemctl --user disable journal-timestamp-monitor.service 2>/dev/null; then
    print "Disabled timestamp monitor service"
  fi

  # Stop and disable auto-creation timer and service
  if systemctl --user stop journal-auto-create.timer 2>/dev/null; then
    print "Stopped auto-creation timer"
  fi
  if systemctl --user disable journal-auto-create.timer 2>/dev/null; then
    print "Disabled auto-creation timer"
  fi
  if systemctl --user stop journal-auto-create.service 2>/dev/null; then
    print "Stopped auto-creation service"
  fi

  # Remove service files
  if [[ -f "$SYSTEMD_DIR/journal-timestamp-monitor.service" ]]; then
    rm "$SYSTEMD_DIR/journal-timestamp-monitor.service"
    print "Removed timestamp monitor service file"
    services_removed=$((services_removed + 1))
  fi

  if [[ -f "$SYSTEMD_DIR/journal-auto-create.service" ]]; then
    rm "$SYSTEMD_DIR/journal-auto-create.service"
    print "Removed auto-creation service file"
    services_removed=$((services_removed + 1))
  fi

  if [[ -f "$SYSTEMD_DIR/journal-auto-create.timer" ]]; then
    rm "$SYSTEMD_DIR/journal-auto-create.timer"
    print "Removed auto-creation timer file"
    services_removed=$((services_removed + 1))
  fi

  if [[ $services_removed -gt 0 ]]; then
    systemctl --user daemon-reload
    print "Journal services uninstalled successfully! ($services_removed files removed)"
  else
    print "No journal service files found. They may have already been uninstalled."
  fi
  exit 0
fi

# Handle opening existing journal entry
if [[ -n "$OPEN_FILE" ]]; then
  print "Opening journal entry: $OPEN_FILE" "INFO"
  
  # Make the file path absolute if it's relative
  if [[ "$OPEN_FILE" != /* ]]; then
    OPEN_FILE="$(pwd)/$OPEN_FILE"
  fi
  
  # Validate file exists and is readable
  if [[ ! -f "$OPEN_FILE" ]]; then
    exit_with_code "GENERAL" "File not found: $OPEN_FILE"
  fi
  
  if [[ ! -r "$OPEN_FILE" ]]; then
    exit_with_code "GENERAL" "File is not readable: $OPEN_FILE"
  fi
  
  # Determine if file is encrypted and choose appropriate editor
  USE_SOPS_FOR_EDITING=false
  file_encrypted=false
  
  # Check encryption status and SOPS availability
  if [[ "$SOPS_AVAILABLE" == "true" ]]; then
    # Detect SOPS config if not already set
    if [[ -z "$SOPS_CONFIG" ]]; then
      if [[ -n "$SOPS_CONFIG_PATH" ]]; then
        SOPS_CONFIG=$(detect_sops_config "$SOPS_CONFIG_PATH" 2>/dev/null || echo "")
      else
        SOPS_CONFIG=$(detect_sops_config 2>/dev/null || echo "")
      fi
    fi
    
    if [[ -n "$SOPS_CONFIG" ]] && is_file_encrypted "$OPEN_FILE"; then
      file_encrypted=true
      USE_SOPS_FOR_EDITING=true
      print "Detected encrypted journal entry" "INFO"
      print "Opening with SOPS editor (will decrypt for editing, re-encrypt on save)" "INFO"
    else
      print "Opening unencrypted journal entry with $EDITOR" "INFO"
    fi
  else
    # SOPS not available, check if file might be encrypted anyway
    if grep -q "sops:" "$OPEN_FILE" 2>/dev/null; then
      print "Warning: File appears to be encrypted but SOPS is not available" "WARN"
      print "The file may not display correctly in a regular editor" "WARN"
      
      if [[ "$QUIET_FAIL" == "false" ]]; then
        read -r -p "Do you want to continue opening with $EDITOR anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
          print "Editor opening cancelled" "INFO"
          exit 0
        fi
      fi
    fi
    
    print "Opening journal entry with $EDITOR" "INFO"
  fi
  
  # Open the file with the appropriate method
  if [[ "$USE_SOPS_FOR_EDITING" == "true" ]]; then
    # Use SOPS to edit encrypted file
    sops_args=()
    if [[ -n "$SOPS_CONFIG" ]]; then
      sops_args+=("--config" "$SOPS_CONFIG")
    fi
    sops_args+=("$OPEN_FILE")
    
    if ! sops "${sops_args[@]}"; then
      print "Warning: SOPS editor exited with an error" "WARN"
      exit 1
    fi
  else
    # Use regular editor for unencrypted file
    if ! command -v "$EDITOR" >/dev/null 2>&1; then
      exit_with_code "GENERAL" "Editor '$EDITOR' not found in PATH"
    fi
    
    if ! "$EDITOR" "$OPEN_FILE"; then
      print "Warning: Editor '$EDITOR' exited with an error" "WARN"
      exit 1
    fi
  fi
  
  print "Journal entry editing completed" "INFO"
  exit 0
fi

# Handle migration to encrypted format
if [[ "$MIGRATE_TO_ENCRYPTED" = true ]]; then
  #
  # migrate_to_encrypted() - Convert existing journal entries to encrypted format
  #
  # Comprehensive migration function that converts unencrypted markdown journal
  # entries to SOPS-encrypted format with extensive validation and error handling.
  #
  # Usage: migrate_to_encrypted
  #
  # Features:
  #   - Prerequisites validation (SOPS availability, configuration)
  #   - Batch processing with progress reporting
  #   - Automatic backup creation before encryption
  #   - Detailed error reporting and recovery
  #   - Summary statistics and operation results
  #
  # Returns:
  #   Exits with 0 on success or appropriate error code on failure
  #
  migrate_to_encrypted() {
    local files_already_encrypted=()
    local files_newly_encrypted=()
    local files_failed=()
    local files_skipped=()
    local processed_count=0
    local total_count=0

    print "Starting migration to encrypted format..." "INFO"

    # Enhanced prerequisites check
    print "Checking prerequisites..." "INFO"

    # Check SOPS availability with guidance
    if [[ "$SOPS_AVAILABLE" == "true" ]]; then
      if ! check_sops_availability_with_guidance; then
        exit_with_code "SOPS" "Migration aborted: SOPS not available"
      fi
    else
      exit_with_code "SOPS" "Migration aborted: SOPS utilities not loaded"
    fi

    # Determine and validate SOPS config
    local sops_config=""
    if [[ -n "$SOPS_CONFIG_PATH" ]]; then
      sops_config=$(detect_sops_config "$SOPS_CONFIG_PATH" 2>/dev/null || echo "")
      if [[ -n "$sops_config" ]]; then
        print "Using custom SOPS config: $sops_config" "INFO"
      else
        exit_with_code "CONFIG" "Custom SOPS config file not found or invalid: $SOPS_CONFIG_PATH"
      fi
    else
      sops_config=$(detect_sops_config 2>/dev/null || echo "")
      if [[ -z "$sops_config" ]]; then
        print "No .sops.yaml configuration found in current directory" "ERROR"
        print "Create a SOPS configuration file first:" "ERROR"
        print "  1. Generate/import encryption keys (Age, PGP, KMS, etc.)" "ERROR"
        print "  2. Create .sops.yaml with creation rules and key configuration" "ERROR"
        print "  3. See: https://github.com/mozilla/sops#usage" "ERROR"
        exit_with_code "CONFIG" "No SOPS configuration found"
      fi
    fi

    # Validate SOPS configuration
    if ! validate_sops_config "$sops_config"; then
      exit_with_code "CONFIG" "Migration aborted: Invalid SOPS configuration"
    fi

    # Test SOPS functionality before proceeding
    print "Testing SOPS encryption functionality..." "INFO"
    if ! test_sops_encryption "$sops_config"; then
      print "Please verify your encryption keys and configuration" "ERROR"
      exit_with_code "SOPS" "Migration aborted: SOPS encryption test failed"
    fi
    print "SOPS functionality test passed" "INFO"

    # Verify target directory
    if [[ ! -d "$OUTPUT_DIR" ]]; then
      exit_with_code "GENERAL" "Target directory does not exist: $OUTPUT_DIR"
    fi

    if [[ ! -w "$OUTPUT_DIR" ]]; then
      exit_with_code "GENERAL" "Target directory is not writable: $OUTPUT_DIR"
    fi

    print "Prerequisites check passed" "INFO"
    print "" "INFO"

    # Find and validate markdown files
    print "Scanning for markdown files in: $OUTPUT_DIR" "INFO"
    local md_files=()
    while IFS= read -r -d '' file; do
      if [[ -f "$file" ]]; then
        md_files+=("$file")
      fi
    done < <(find "$OUTPUT_DIR" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)

    total_count=${#md_files[@]}
    if [[ $total_count -eq 0 ]]; then
      print "No markdown files found in directory: $OUTPUT_DIR" "WARN"
      print "Migration completed with no files to process" "INFO"
      exit 0
    fi

    print "Found $total_count markdown files to process" "INFO"

    # Show progress estimate
    if [[ $total_count -gt 10 ]]; then
      print "This may take a moment for large numbers of files..." "INFO"
    fi

    print "" "INFO"

    # Process each file with enhanced error handling
    for file_path in "${md_files[@]}"; do
      local filename
      filename=$(basename "$file_path")
      processed_count=$((processed_count + 1))

      # Show progress with percentage for large batches
      if [[ $total_count -gt 20 ]]; then
        local percentage=$((processed_count * 100 / total_count))
        print "[$processed_count/$total_count] ($percentage%) Processing: $filename" "INFO"
      else
        print "[$processed_count/$total_count] Processing: $filename" "INFO"
      fi

      # Validate file accessibility
      if [[ ! -r "$file_path" ]]; then
        print "Skipping unreadable file: $filename" "WARN"
        files_failed+=("$filename (unreadable)")
        continue
      fi

      if [[ ! -w "$file_path" ]]; then
        print "Skipping unwritable file: $filename" "WARN"
        files_failed+=("$filename (unwritable)")
        continue
      fi

      # Check file size (empty files)
      if [[ ! -s "$file_path" ]]; then
        print "Skipping empty file: $filename" "WARN"
        files_skipped+=("$filename (empty)")
        continue
      fi

      # Check if file is already encrypted
      if is_file_encrypted "$file_path"; then
        print "Already encrypted: $filename" "DEBUG"
        files_already_encrypted+=("$filename")
        continue
      fi

      # Create backup before encryption
      local backup_file
      backup_file="${file_path}.backup.$(date +%s)"
      if ! cp "$file_path" "$backup_file" 2>/dev/null; then
        print "Failed to create backup for: $filename" "ERROR"
        files_failed+=("$filename (backup failed)")
        continue
      fi

      # Attempt encryption with detailed error capture
      print "Encrypting: $filename" "DEBUG"
      local sops_error
      sops_migrate_args=("--encrypt" "--in-place")
      if [[ -n "$sops_config" ]]; then
        sops_migrate_args+=("--config" "$sops_config")
      fi
      sops_migrate_args+=("$file_path")
      
      if sops_error=$(sops "${sops_migrate_args[@]}" 2>&1); then
        print "Successfully encrypted: $filename" "DEBUG"
        files_newly_encrypted+=("$filename")
        # Remove backup on success
        rm -f "$backup_file" 2>/dev/null
      else
        print "Failed to encrypt: $filename" "ERROR"

        # Restore from backup
        if [[ -f "$backup_file" ]]; then
          mv "$backup_file" "$file_path" 2>/dev/null || true
          print "Restored from backup: $filename" "INFO"
        fi

        # Provide specific error guidance
        get_sops_error_guidance "$sops_error"

        files_failed+=("$filename")
      fi
    done

    # Enhanced summary with detailed statistics
    print "" "INFO"
    print "=== Migration Summary ===" "INFO"
    print "Total files processed: $processed_count" "INFO"
    print "Files already encrypted: ${#files_already_encrypted[@]}" "INFO"
    print "Files newly encrypted: ${#files_newly_encrypted[@]}" "INFO"
    print "Files skipped: ${#files_skipped[@]}" "INFO"
    print "Files failed: ${#files_failed[@]}" "INFO"

    # Show details for newly encrypted files
    if [[ ${#files_newly_encrypted[@]} -gt 0 ]]; then
      print "" "INFO"
      print "Newly encrypted files:" "INFO"
      for file in "${files_newly_encrypted[@]}"; do
        print "  ✓ $file" "INFO"
      done
    fi

    # Show details for already encrypted files (in debug mode)
    if [[ ${#files_already_encrypted[@]} -gt 0 && "$JOURNAL_LOG_LEVEL" == "DEBUG" ]]; then
      print "" "INFO"
      print "Already encrypted files:" "INFO"
      for file in "${files_already_encrypted[@]}"; do
        print "  - $file" "INFO"
      done
    fi

    # Show details for skipped files
    if [[ ${#files_skipped[@]} -gt 0 ]]; then
      print "" "WARN"
      print "Skipped files:" "WARN"
      for file in "${files_skipped[@]}"; do
        print "  ~ $file" "WARN"
      done
    fi

    # Show details for failed files
    if [[ ${#files_failed[@]} -gt 0 ]]; then
      print "" "ERROR"
      print "Failed files:" "ERROR"
      for file in "${files_failed[@]}"; do
        print "  ✗ $file" "ERROR"
      done
      print "" "ERROR"
      exit_with_code "SOPS" "Migration completed with errors. Please review failed files above."
    fi

    # Success message
    if [[ ${#files_newly_encrypted[@]} -gt 0 ]]; then
      print "" "INFO"
      print "Migration completed successfully! ${#files_newly_encrypted[@]} files newly encrypted." "INFO"
    else
      print "" "INFO"
      print "Migration completed. No new files needed encryption." "INFO"
    fi

    exit 0
  }

  # Execute the migration function
  migrate_to_encrypted
fi

# Enhanced SOPS configuration detection and validation
SOPS_CONFIG=""
SOPS_ENCRYPTION_ENABLED=false
if [[ "$SOPS_AVAILABLE" == "true" ]]; then
  # Enhanced sops availability check with user guidance
  if check_sops_availability_with_guidance; then
    print "SOPS executable available: $SOPS_VERSION" "DEBUG"

    # Use custom SOPS config path if provided via parameter, environment, or auto-detect
    config_source=""
    if [[ -n "$SOPS_CONFIG_PATH" ]]; then
      # Command line parameter takes precedence
      SOPS_CONFIG=$(detect_sops_config "$SOPS_CONFIG_PATH" 2>/dev/null || echo "")
      config_source="command line parameter"
    elif [[ -n "${SOPS_CONFIG_PATH:-}" ]]; then
      # Environment variable (e.g., from systemd service)
      SOPS_CONFIG=$(detect_sops_config "${SOPS_CONFIG_PATH}" 2>/dev/null || echo "")
      config_source="environment variable"
    else
      # Auto-detect
      SOPS_CONFIG=$(detect_sops_config 2>/dev/null || echo "")
      config_source="auto-detection"
    fi

    if [[ -n "$SOPS_CONFIG" ]]; then
      print "Using SOPS config from $config_source: $SOPS_CONFIG" "DEBUG"
    elif [[ -n "$SOPS_CONFIG_PATH" ]]; then
      print "Please ensure the path is correct and the file exists" "ERROR"
      exit_with_code "CONFIG" "Custom SOPS config path provided but no config found: $SOPS_CONFIG_PATH"
    fi

    if [[ -n "$SOPS_CONFIG" ]]; then
      # Validate SOPS configuration
      if validate_sops_config "$SOPS_CONFIG"; then
        # Test encryption functionality
        if test_sops_encryption "$SOPS_CONFIG"; then
          SOPS_ENCRYPTION_ENABLED=true
          print "SOPS encryption enabled and tested successfully (config: $SOPS_CONFIG)" "DEBUG"
        else
          print "SOPS config found but encryption test failed" "ERROR"
          print "Check your encryption keys and configuration" "ERROR"
          get_sops_error_guidance "encryption test failed"
          exit_with_code "SOPS" "Cannot proceed with invalid SOPS configuration"
        fi
      else
        print "SOPS config found but validation failed" "ERROR"
        print "Please check your .sops.yaml configuration file" "ERROR"
        exit_with_code "CONFIG" "Cannot proceed with invalid SOPS configuration"
      fi
    else
      print "Operating in unencrypted mode (no .sops.yaml found)" "INFO"
      if [[ "$QUIET_FAIL" == "false" ]]; then
        print "To enable encryption, create a .sops.yaml file. See: https://github.com/mozilla/sops#usage" "INFO"
      fi
    fi
  else
    print "SOPS executable not available - operating in unencrypted mode" "DEBUG"
  fi
else
  print "Operating in unencrypted mode (SOPS utilities not available)" "DEBUG"
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

#
# get_start_date() - Get or initialize the start date configuration
#
# Reads the start date from configuration file or prompts user to set it
# for first-time setup. Uses interactive prompts unless in quiet mode.
#
# Usage: get_start_date
#
# Returns:
#   Prints the start date to stdout, exits on configuration errors
#
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
    exit_with_code "GENERAL" "Failed to create output directory: $OUTPUT_DIR"
  fi

  print "Created output directory: $OUTPUT_DIR" "INFO"
else
  if [[ ! -w "$OUTPUT_DIR" ]]; then
    exit_with_code "GENERAL" "Output directory is not writable: $OUTPUT_DIR"
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

# Enhanced encryption handling with atomic operations
if [[ "$SOPS_ENCRYPTION_ENABLED" == "true" ]]; then
  print "Encrypting journal entry with SOPS..." "INFO"

  # Attempt encryption with detailed error handling
  sops_error=""
  sops_encrypt_args=("--encrypt" "--in-place")
  if [[ -n "$SOPS_CONFIG" ]]; then
    sops_encrypt_args+=("--config" "$SOPS_CONFIG")
  fi
  sops_encrypt_args+=("$OUTPUT_FILE")
  
  if sops_error=$(sops "${sops_encrypt_args[@]}" 2>&1); then
    print "Journal entry encrypted successfully" "INFO"
    print "File saved as encrypted: $OUTPUT_FILE" "INFO"
  else
    print "Failed to encrypt journal entry with SOPS" "ERROR"

    # Remove the partial file to ensure atomic operation
    rm -f "$OUTPUT_FILE" 2>/dev/null

    # Provide specific error guidance
    get_sops_error_guidance "$sops_error"

    exit_with_code "SOPS" "Cannot create journal entry: encryption failed"
  fi
else
  # Notify user about encryption status
  if [[ "$QUIET_FAIL" == "false" ]]; then
    if [[ "$SOPS_AVAILABLE" == "true" ]]; then
      print "Journal entry created as unencrypted (no SOPS config or encryption disabled)" "INFO"
    else
      print "Journal entry created as unencrypted (SOPS not available)" "DEBUG"
    fi
  fi
fi

if [[ "$OPEN_EDITOR" = true ]]; then
  if [[ ! -f "$OUTPUT_FILE" ]]; then
    print "Error: Journal entry file no longer exists: $OUTPUT_FILE" "ERROR"
    exit 1
  fi

  if [[ ! -r "$OUTPUT_FILE" ]]; then
    print "Error: Journal entry is not readable: $OUTPUT_FILE" "ERROR"
    exit 1
  fi

  # Enhanced editor selection with encryption status awareness
  USE_SOPS_FOR_EDITING=false
  file_encrypted=false

  # Check encryption status with user-friendly messaging
  if [[ "$SOPS_AVAILABLE" == "true" ]] && [[ -n "$SOPS_CONFIG" ]]; then
    if is_file_encrypted "$OUTPUT_FILE"; then
      file_encrypted=true
      USE_SOPS_FOR_EDITING=true
      print "Detected encrypted journal entry" "INFO"
      print "Opening with SOPS editor (will decrypt for editing, re-encrypt on save)" "INFO"
    else
      print "Opening unencrypted journal entry in $EDITOR" "INFO"
    fi
  else
    # SOPS not available, check if file might be encrypted anyway
    if grep -q "sops:" "$OUTPUT_FILE" 2>/dev/null; then
      print "Warning: File appears to be encrypted but SOPS is not available" "WARN"
      print "The file may not display correctly in a regular editor" "WARN"

      if [[ "$QUIET_FAIL" == "false" ]]; then
        read -r -p "Do you want to continue opening with $EDITOR anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
          print "Editor opening cancelled. Your journal entry is saved at: $OUTPUT_FILE" "INFO"
          exit 0
        fi
      fi
    fi

    # Check if editor is available
    if ! command -v "$EDITOR" >/dev/null 2>&1; then
      print "Error: Editor '$EDITOR' not found, cannot open journal entry" "ERROR"
      print "You can still find your journal entry at: $OUTPUT_FILE" "INFO"
      print "Set the EDITOR environment variable or use -E option to specify an editor" "INFO"
      exit 1
    fi

    print "Opening journal entry in $EDITOR" "INFO"
  fi

  # Open the file with the appropriate method
  if [[ "$USE_SOPS_FOR_EDITING" == "true" ]]; then
    if ! sops "$OUTPUT_FILE"; then
      print "Warning: SOPS editor exited with an error" "WARN"
      print "Your journal entry was created successfully at: $OUTPUT_FILE" "INFO"
      exit 1
    fi
  else
    if ! command -v "$EDITOR" >/dev/null 2>&1; then
      print "Error: Editor '$EDITOR' not found, cannot open journal entry" "ERROR"
      print "You can still find your journal entry at: $OUTPUT_FILE" "INFO"
      exit 1
    fi

    if ! "$EDITOR" "$OUTPUT_FILE"; then
      print "Warning: Editor '$EDITOR' exited with an error" "WARN"
      print "Your journal entry was created successfully at: $OUTPUT_FILE" "INFO"
      exit 1
    fi
  fi
fi

exit 0