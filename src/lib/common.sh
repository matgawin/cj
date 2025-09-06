#!/usr/bin/env bash

JOURNAL_LOG_FILE="${HOME}/.local/share/journal/journal.log"
JOURNAL_LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR, NONE

error_exit() {
    local message="$1"
    local exit_code="${2:-1}"

    log "ERROR" "Error: ${message} (exit code: ${exit_code})"

    echo "Error: ${message}" >&2
    exit "${exit_code}"
}

check_command() {
    local command="$1"
    local message="${2:-Command failed: $1}"

    if ! eval "$command"; then
        error_exit "$message" 2
    fi
}

check_dependency() {
    local cmd="$1"
    local package="${2:-$1}"

    if ! command -v "$cmd" &>/dev/null; then
        log "WARN" "Dependency not found: $cmd"
        echo "Warning: Required dependency '$cmd' not found."
        echo "Please install it with your package manager (e.g., 'apt install $package', 'brew install $package')"
        return 1
    fi
    return 0
}

ensure_dir() {
    local dir="$1"
    local message="${2:-Could not create directory: $1}"

    if [ ! -d "$dir" ]; then
        log "DEBUG" "Creating directory: $dir"
        if ! mkdir -p "$dir" 2>/dev/null; then
            error_exit "$message" 3
        fi
    fi
}

validate_file() {
    local file="$1"
    local expected_type="$2"
    local message="${3:-Invalid file: $1}"

    case "$expected_type" in
        "file")
            [ -f "$file" ] || error_exit "$message" 4
            ;;
        "dir"|"directory")
            [ -d "$file" ] || error_exit "$message" 4
            ;;
        "executable")
            [ -x "$file" ] || error_exit "$message" 4
            ;;
        "readable")
            [ -r "$file" ] || error_exit "$message" 4
            ;;
        "writable")
            [ -w "$file" ] || error_exit "$message" 4
            ;;
        *)
            [ -e "$file" ] || error_exit "$message" 4
            ;;
    esac
}

validate_input() {
    local input="$1"
    local pattern="$2"
    local message="${3:-Invalid input format: $1}"

    if [[ ! "$input" =~ $pattern ]]; then
        error_exit "$message" 5
    fi
}

confirm_action() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        local options="Y/n"
    else
        local options="y/N"
    fi

    read -r -p "$prompt ($options): " response
    response="${response:-$default}"

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

setup_logging() {
    local log_dir
    log_dir=$(dirname "$JOURNAL_LOG_FILE")
    mkdir -p "$log_dir" 2>/dev/null || {
        echo "Warning: Could not create log directory $log_dir" >&2
        JOURNAL_LOG_FILE="/tmp/journal.log"
    }

    if [ ! -f "$JOURNAL_LOG_FILE" ]; then
        touch "$JOURNAL_LOG_FILE" 2>/dev/null || {
            echo "Warning: Could not create log file $JOURNAL_LOG_FILE" >&2
            JOURNAL_LOG_FILE="/tmp/journal.log"
            touch "$JOURNAL_LOG_FILE"
        }
    fi
}

log() {
    local level="$1"
    local message="$2"
    local timestamp

    case "$level" in
        "DEBUG") level_num=1 ;;
        "INFO")  level_num=2 ;;
        "WARN")  level_num=3 ;;
        "ERROR") level_num=4 ;;
        *)       level_num=2 ;; # Default to INFO
    esac

    case "$JOURNAL_LOG_LEVEL" in
        "DEBUG") config_level=1 ;;
        "INFO")  config_level=2 ;;
        "WARN")  config_level=3 ;;
        "ERROR") config_level=4 ;;
        "NONE")  config_level=5 ;;
        *)       config_level=2 ;; # Default to INFO
    esac

    if [ "$level_num" -ge "$config_level" ]; then
        if [ "$config_level" -lt 5 ]; then  # Don't log if NONE
            timestamp=$(date "+%Y-%m-%d %H:%M:%S")
            echo "[${timestamp}] [${level}] ${message}" >> "$JOURNAL_LOG_FILE"
        fi
    fi
}

setup_logging