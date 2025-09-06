#!/bin/bash
set -e

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
  JOURNAL_LOG_FILE="/tmp/journal_timestamp_monitor.log"
  touch "$JOURNAL_LOG_FILE"

  log() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] - $message" >>"$JOURNAL_LOG_FILE"
  }

  error_exit() {
    local message="$1"
    local exit_code="${2:-1}"

    log "ERROR" "Error: ${message} (exit code: ${exit_code})"
    echo "Error: ${message}" >&2
    exit "${exit_code}"
  }

  ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
      if ! mkdir -p "$dir" 2>/dev/null; then
        error_exit "Could not create directory: $dir" 3
      fi
    fi
  }

  validate_file() {
    local file="$1"
    local expected_type="$2"
    local message="${3:-Invalid file: $1}"

    case "$expected_type" in
      "dir"|"directory")
        [ -d "$file" ] || error_exit "$message" 4
        ;;
      *)
        [ -e "$file" ] || error_exit "$message" 4
        ;;
    esac
  }
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
SOPS_CONFIG=""
SOPS_ENCRYPTION_ENABLED=false
if [[ -f "${SOPS_LIB}" ]]; then
  # shellcheck disable=SC1090
  source "${SOPS_LIB}" 2>/dev/null && SOPS_AVAILABLE=true
  
  if [[ "$SOPS_AVAILABLE" == "true" ]]; then
    if check_sops_available; then
      # Use environment variable if set, otherwise auto-detect
      if [[ -n "$SOPS_CONFIG_PATH" ]]; then
        SOPS_CONFIG=$(detect_sops_config "$SOPS_CONFIG_PATH" 2>/dev/null || echo "")
        if [[ -n "$SOPS_CONFIG" ]]; then
          log "DEBUG" "Using SOPS config from environment: $SOPS_CONFIG"
        else
          log "WARN" "SOPS config path specified in environment but not found: $SOPS_CONFIG_PATH"
        fi
      else
        SOPS_CONFIG=$(detect_sops_config 2>/dev/null || echo "")
        if [[ -n "$SOPS_CONFIG" ]]; then
          log "DEBUG" "Auto-detected SOPS config: $SOPS_CONFIG"
        fi
      fi
      
      if [[ -n "$SOPS_CONFIG" ]]; then
        if validate_sops_config "$SOPS_CONFIG"; then
          SOPS_ENCRYPTION_ENABLED=true
          log "DEBUG" "SOPS encryption support enabled for timestamp monitor"
        else
          log "WARN" "SOPS config found but invalid - continuing without encryption support"
        fi
      else
        log "DEBUG" "No SOPS config found - continuing without encryption support"
      fi
    else
      log "WARN" "SOPS executable not available - continuing without encryption support"
    fi
  fi
fi

JOURNAL_LOG_LEVEL="INFO"

JOURNAL_DIR="$1"
if [ -z "$JOURNAL_DIR" ]; then
  error_exit "Journal directory not specified. Usage: $0 <journal_directory>" 1
fi

ensure_dir "$JOURNAL_DIR"
validate_file "$JOURNAL_DIR" "directory" "Journal directory does not exist or is not accessible: $JOURNAL_DIR"

log "INFO" "Starting journal timestamp monitor for directory: $JOURNAL_DIR"

update_timestamp() {
  local file="$1"
  local current_time
  local file_is_encrypted=false

  if [[ ! -f "$file" ]]; then
    log "WARN" "File does not exist: $file"
    return 1
  fi

  if [[ ! -r "$file" ]]; then
    log "WARN" "File is not readable: $file"
    return 1
  fi

  if [[ ! -w "$file" ]]; then
    log "WARN" "File is not writable: $file"
    return 1
  fi

  current_time=$(date +"%Y-%m-%d, %H:%M:%S")

  if [[ "$file" != *.md ]]; then
    log "DEBUG" "Skipping non-markdown file: $file"
    return 0
  fi

  # Check if file is encrypted
  if [[ "$SOPS_ENCRYPTION_ENABLED" == "true" ]] && is_file_encrypted "$file"; then
    file_is_encrypted=true
    log "DEBUG" "Processing encrypted file: $file"
  fi

  # Handle encrypted files
  if [[ "$file_is_encrypted" == "true" ]]; then
    if [[ "$SOPS_AVAILABLE" != "true" ]]; then
      log "WARN" "File appears encrypted but SOPS not available: $file"
      return 1
    fi

    # Create temporary file for decrypted content
    temp_file
    temp_file=$(mktemp) || {
      log "ERROR" "Failed to create temporary file for encrypted file: $file"
      return 1
    }

    # Decrypt to temporary file
    if ! sops --decrypt "$file" > "$temp_file" 2>/dev/null; then
      log "ERROR" "Failed to decrypt file: $file"
      rm -f "$temp_file" 2>/dev/null
      return 1
    fi

    # Check if decrypted content has proper frontmatter and updated field
    if ! grep -q "^---$" "$temp_file" || [[ $(grep -c "^---$" "$temp_file") -lt 2 ]]; then
      log "DEBUG" "Skipping encrypted file without proper YAML frontmatter: $file"
      rm -f "$temp_file" 2>/dev/null
      return 0
    fi

    if ! grep -q "^updated:" "$temp_file"; then
      log "WARN" "Encrypted file does not have 'updated:' field in frontmatter: $file"
      rm -f "$temp_file" 2>/dev/null
      return 0
    fi

    log "INFO" "Updating timestamp for encrypted file: $file"

    # Update timestamp in decrypted content
    if [[ "$(uname)" == "Darwin" ]]; then
      if ! sed -i "" "s/^updated:.*$/updated: $current_time/" "$temp_file"; then
        log "ERROR" "Failed to update timestamp in decrypted content: $file"
        rm -f "$temp_file" 2>/dev/null
        return 1
      fi
    else
      if ! sed -i "s/^updated:.*$/updated: $current_time/" "$temp_file"; then
        log "ERROR" "Failed to update timestamp in decrypted content: $file"
        rm -f "$temp_file" 2>/dev/null
        return 1
      fi
    fi

    # Re-encrypt the updated content
    if ! sops --encrypt --in-place "$temp_file" 2>/dev/null; then
      log "ERROR" "Failed to re-encrypt updated content: $file"
      rm -f "$temp_file" 2>/dev/null
      return 1
    fi

    # Atomically replace the original file
    if ! mv "$temp_file" "$file" 2>/dev/null; then
      log "ERROR" "Failed to replace encrypted file with updated version: $file"
      rm -f "$temp_file" 2>/dev/null
      return 1
    fi

    log "DEBUG" "Successfully updated timestamp in encrypted file: $file"
    return 0
  else
    # Handle unencrypted files (original logic)
    if ! grep -q "^---$" "$file" || [[ $(grep -c "^---$" "$file") -lt 2 ]]; then
      log "DEBUG" "Skipping file without proper YAML frontmatter: $file"
      return 0
    fi

    if ! grep -q "^updated:" "$file"; then
      log "WARN" "File does not have 'updated:' field in frontmatter: $file"
      return 0
    fi

    log "INFO" "Updating timestamp for file: $file"

    if [[ "$(uname)" == "Darwin" ]]; then
      if ! sed -i "" "s/^updated:.*$/updated: $current_time/" "$file"; then
        log "ERROR" "Failed to update timestamp in file: $file"
        return 1
      fi
    else
      if ! sed -i "s/^updated:.*$/updated: $current_time/" "$file"; then
        log "ERROR" "Failed to update timestamp in file: $file"
        return 1
      fi
    fi

    log "DEBUG" "Successfully updated timestamp in file: $file"
    return 0
  fi
}

MONITORING_INTERVAL=60 # Default monitoring interval in seconds

check_modified_files() {
  local dir="$1"
  local interval="${2:-1}"

  log "DEBUG" "Checking for files modified in the last $interval minute(s)"

  if ! command -v find >/dev/null 2>&1; then
    log "ERROR" "Required dependency 'find' not found"
    error_exit "Required dependency 'find' not found. Cannot monitor files." 5
  fi

  find "$dir" -name "*.md" -mmin -"$interval" 2>/dev/null | while read -r file; do
    update_timestamp "$file"
  done
}

# Use inotifywait if available, otherwise fallback to periodic checking
if command -v inotifywait >/dev/null 2>&1; then
  log "INFO" "Using inotifywait for file monitoring"

  while true; do
    log "DEBUG" "Starting inotify monitoring on $JOURNAL_DIR"

    if [[ ! -d "$JOURNAL_DIR" ]]; then
      log "ERROR" "Journal directory no longer exists: $JOURNAL_DIR"
      error_exit "Journal directory no longer exists: $JOURNAL_DIR" 6
    fi

    if ! timeout 3600 inotifywait -q -m -e modify -e close_write --format "%w%f" "$JOURNAL_DIR" 2>/dev/null | while read -r file; do
      if [[ "$file" == *.md ]]; then
        log "DEBUG" "File modified: $file"
        update_timestamp "$file"
      fi
    done; then
      log "WARN" "inotifywait monitoring interrupted, restarting in 5 seconds"
      sleep 5
    fi

    log "INFO" "Restarting inotify monitoring after timeout period"
  done
else
  log "INFO" "inotifywait not found, using periodic checking instead"

  if [[ -n "$JOURNAL_POLLING_INTERVAL" && "$JOURNAL_POLLING_INTERVAL" =~ ^[0-9]+$ ]]; then
    MONITORING_INTERVAL="$JOURNAL_POLLING_INTERVAL"
    log "INFO" "Using custom polling interval: $MONITORING_INTERVAL seconds"
  fi

  log "WARN" "For better performance, consider installing inotify-tools package"
  echo "Recommendation: For better performance, consider installing inotify-tools package" >&2

  while true; do
    if [[ ! -d "$JOURNAL_DIR" ]]; then
      log "ERROR" "Journal directory no longer exists: $JOURNAL_DIR"
      error_exit "Journal directory no longer exists: $JOURNAL_DIR" 6
    fi

    interval_min=$(( MONITORING_INTERVAL / 60 ))
    if [[ $interval_min -lt 1 ]]; then
      interval_min=1
    fi

    check_modified_files "$JOURNAL_DIR" "$interval_min"

    log "DEBUG" "Sleeping for $MONITORING_INTERVAL seconds before next check"
    sleep "$MONITORING_INTERVAL"
  done
fi
