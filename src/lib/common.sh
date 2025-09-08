#!/usr/bin/env bash
#
# common.sh - Common utilities and functions for journal management system
#
# This script provides essential utilities and functions used across the journal
# management system, including error handling, file validation, user interaction,
# and logging functionality.
#
# Functions:
#   - error_exit()           Exit with error message and optional exit code
#   - check_command()        Execute and validate command success
#   - check_dependency()     Verify system dependency availability
#   - ensure_dir()           Create directory if it doesn't exist
#   - validate_file()        Validate file existence and properties
#   - validate_input()       Validate input against pattern
#   - confirm_action()       Interactive confirmation prompt
#   - setup_logging()        Initialize logging system
#   - log()                  Log messages with level filtering
#

JOURNAL_LOG_FILE="${HOME}/.local/share/journal/journal.log"
JOURNAL_LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR, NONE

#
# error_exit() - Exit the script with an error message and optional exit code
#
# Usage: error_exit <message> [exit_code]
#
# Parameters:
#   message   - Error message to display
#   exit_code - Optional exit code (default: 1)
#
# Returns:
#   Exits the script with the specified exit code
#
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"

    log "ERROR" "Error: ${message} (exit code: ${exit_code})"

    echo "Error: ${message}" >&2
    exit "${exit_code}"
}

#
# check_command() - Execute a command and exit with error if it fails
#
# Usage: check_command <command> [error_message]
#
# Parameters:
#   command       - Command to execute and validate
#   error_message - Optional custom error message (default: "Command failed: <command>")
#
# Returns:
#   0 on success, calls error_exit with code 2 on failure
#
check_command() {
    local command="$1"
    local message="${2:-Command failed: $1}"

    if ! eval "$command"; then
        error_exit "$message" 2
    fi
}

#
# check_dependency() - Check if a system dependency is available
#
# Usage: check_dependency <command> [package_name]
#
# Parameters:
#   command      - Command/executable to check for availability
#   package_name - Optional package name for installation instructions (default: same as command)
#
# Returns:
#   0 if dependency is available, 1 if not found
#
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

#
# ensure_dir() - Create directory if it doesn't exist
#
# Usage: ensure_dir <directory> [error_message]
#
# Parameters:
#   directory     - Directory path to create
#   error_message - Optional custom error message (default: "Could not create directory: <directory>")
#
# Returns:
#   0 if directory exists or is created successfully, calls error_exit with code 3 on failure
#
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

#
# validate_file() - Validate file existence and properties
#
# Usage: validate_file <file_path> <expected_type> [error_message]
#
# Parameters:
#   file_path     - Path to file/directory to validate
#   expected_type - Type of validation: "file", "dir"/"directory", "executable", "readable", "writable", or any other for existence check
#   error_message - Optional custom error message (default: "Invalid file: <file_path>")
#
# Returns:
#   0 if validation passes, calls error_exit with code 4 on failure
#
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

#
# validate_input() - Validate input against a regex pattern
#
# Usage: validate_input <input> <pattern> [error_message]
#
# Parameters:
#   input         - Input string to validate
#   pattern       - Regex pattern to match against
#   error_message - Optional custom error message (default: "Invalid input format: <input>")
#
# Returns:
#   0 if input matches pattern, calls error_exit with code 5 on failure
#
validate_input() {
    local input="$1"
    local pattern="$2"
    local message="${3:-Invalid input format: $1}"

    if [[ ! "$input" =~ $pattern ]]; then
        error_exit "$message" 5
    fi
}

#
# confirm_action() - Interactive confirmation prompt with default value
#
# Usage: confirm_action <prompt> [default]
#
# Parameters:
#   prompt  - Prompt message to display to user
#   default - Default response if user presses Enter ("y" or "n", default: "n")
#
# Returns:
#   0 if user confirms (y/Y), 1 if user declines (n/N) or on default "n"
#
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

#
# setup_logging() - Initialize the logging system
#
# Creates the log directory and file if they don't exist. Falls back to /tmp/journal.log
# if the default location is not accessible.
#
# Usage: setup_logging
#
# Returns:
#   Always returns 0, but may modify JOURNAL_LOG_FILE global variable as fallback
#
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

#
# log() - Log messages with level-based filtering
#
# Usage: log <level> <message>
#
# Parameters:
#   level   - Log level: DEBUG, INFO, WARN, ERROR (default: INFO if invalid)
#   message - Message to log
#
# Behavior:
#   Only logs messages at or above the configured JOURNAL_LOG_LEVEL.
#   Uses JOURNAL_LOG_FILE for output. Timestamps are automatically added.
#
# Returns:
#   Always returns 0
#
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