#!/usr/bin/env bash
#
# error_handling.sh - Standardized error handling and exit codes for journal management
#
# This module provides consistent error handling, exit codes, and error message formatting
# across all journal management scripts.
#

# Standardized exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_SOPS_ERROR=2
readonly EXIT_CONFIG_ERROR=3
readonly EXIT_SERVICE_ERROR=4

# Error categories and their corresponding exit codes
declare -A ERROR_CATEGORIES=(
    ["SUCCESS"]=$EXIT_SUCCESS
    ["GENERAL"]=$EXIT_GENERAL_ERROR
    ["SOPS"]=$EXIT_SOPS_ERROR
    ["CONFIG"]=$EXIT_CONFIG_ERROR
    ["SERVICE"]=$EXIT_SERVICE_ERROR
)

#
# exit_with_code() - Exit with standardized exit code and optional message
#
# Usage: exit_with_code CATEGORY [message]
#
# Parameters:
#   CATEGORY - One of: SUCCESS, GENERAL, SOPS, CONFIG, SERVICE
#   message  - Optional error message to display
#
exit_with_code() {
    local category="$1"
    local message="$2"

    local exit_code=${ERROR_CATEGORIES[$category]:-$EXIT_GENERAL_ERROR}

    if [[ -n "$message" && "$category" != "SUCCESS" ]]; then
        if type -t print >/dev/null 2>&1; then
            print "$message" "ERROR"
        else
            echo "Error: $message" >&2
        fi
    fi

    exit "$exit_code"
}

#
# error_exit() - Legacy compatibility function
#
# Usage: error_exit message [exit_code]
#
error_exit() {
    local message="$1"
    local exit_code="${2:-$EXIT_GENERAL_ERROR}"

    # Determine category based on exit code
    local category="GENERAL"
    case $exit_code in
        "$EXIT_SUCCESS") category="SUCCESS" ;;
        "$EXIT_SOPS_ERROR") category="SOPS" ;;
        "$EXIT_CONFIG_ERROR") category="CONFIG" ;;
        "$EXIT_SERVICE_ERROR") category="SERVICE" ;;
    esac

    exit_with_code "$category" "$message"
}

#
# validate_sops_operation() - Standardized SOPS error handling
#
# Usage: validate_sops_operation command_output exit_code operation_description
#
validate_sops_operation() {
    local output="$1"
    local exit_code="$2"
    local operation="$3"

    if [[ $exit_code -eq 0 ]]; then
        return 0
    fi

    # Parse common SOPS error patterns
    if echo "$output" | grep -q "no creation rule"; then
        exit_with_code "SOPS" "SOPS configuration error: No creation rule matched for $operation. Check your .sops.yaml file."
    elif echo "$output" | grep -q "no key could decrypt"; then
        exit_with_code "SOPS" "SOPS decryption error: No accessible keys found for $operation. Verify your private keys are available."
    elif echo "$output" | grep -q "config file not found"; then
        exit_with_code "CONFIG" "SOPS configuration file not found. Create a .sops.yaml file in your journal directory."
    elif echo "$output" | grep -q -i "permission denied"; then
        exit_with_code "GENERAL" "Permission denied during $operation. Check file and directory permissions."
    else
        exit_with_code "SOPS" "SOPS $operation failed: $output"
    fi
}

#
# validate_file_operation() - Standardized file operation error handling
#
# Usage: validate_file_operation exit_code operation_description file_path
#
validate_file_operation() {
    local exit_code="$1"
    local operation="$2"
    local file_path="$3"

    if [[ $exit_code -eq 0 ]]; then
        return 0
    fi

    case $exit_code in
        1) exit_with_code "GENERAL" "File operation failed: $operation for '$file_path'" ;;
        2) exit_with_code "GENERAL" "File not found: '$file_path'" ;;
        13) exit_with_code "GENERAL" "Permission denied: Cannot $operation '$file_path'" ;;
        *) exit_with_code "GENERAL" "Unexpected error during $operation of '$file_path' (exit code: $exit_code)" ;;
    esac
}

#
# validate_config_file() - Standardized configuration file validation
#
# Usage: validate_config_file file_path config_type
#
validate_config_file() {
    local file_path="$1"
    local config_type="${2:-configuration}"

    if [[ ! -f "$file_path" ]]; then
        exit_with_code "CONFIG" "$config_type file not found: '$file_path'"
    fi

    if [[ ! -r "$file_path" ]]; then
        exit_with_code "CONFIG" "$config_type file is not readable: '$file_path'"
    fi
}

#
# validate_directory() - Standardized directory validation
#
# Usage: validate_directory dir_path operation_type
#
validate_directory() {
    local dir_path="$1"
    local operation="${2:-access}"

    if [[ ! -d "$dir_path" ]]; then
        exit_with_code "GENERAL" "Directory does not exist: '$dir_path'"
    fi

    if [[ "$operation" == "write" && ! -w "$dir_path" ]]; then
        exit_with_code "GENERAL" "Directory is not writable: '$dir_path'"
    fi

    if [[ "$operation" == "read" && ! -r "$dir_path" ]]; then
        exit_with_code "GENERAL" "Directory is not readable: '$dir_path'"
    fi
}

#
# validate_service_operation() - Standardized service operation validation
#
# Usage: validate_service_operation exit_code operation service_name
#
validate_service_operation() {
    local exit_code="$1"
    local operation="$2"
    local service_name="$3"

    if [[ $exit_code -eq 0 ]]; then
        return 0
    fi

    case $exit_code in
        1) exit_with_code "SERVICE" "Service $operation failed for '$service_name'" ;;
        3) exit_with_code "SERVICE" "Service '$service_name' not found" ;;
        4) exit_with_code "SERVICE" "Insufficient permissions for service $operation of '$service_name'" ;;
        *) exit_with_code "SERVICE" "Service $operation error for '$service_name' (exit code: $exit_code)" ;;
    esac
}

#
# format_error_message() - Standardized error message formatting
#
# Usage: format_error_message category message [details]
#
format_error_message() {
    local category="$1"
    local message="$2"
    local details="$3"

    local prefix
    case "$category" in
        "SOPS") prefix="Encryption Error" ;;
        "CONFIG") prefix="Configuration Error" ;;
        "SERVICE") prefix="Service Error" ;;
        *) prefix="Error" ;;
    esac

    echo "$prefix: $message"
    if [[ -n "$details" ]]; then
        echo "Details: $details"
    fi
}

#
# print_error_help() - Print contextual help for common error categories
#
# Usage: print_error_help category
#
print_error_help() {
    local category="$1"

    case "$category" in
        "SOPS")
            echo
            echo "SOPS Troubleshooting:"
            echo "  1. Ensure SOPS is installed and in PATH"
            echo "  2. Verify .sops.yaml configuration exists and is valid"
            echo "  3. Check that encryption keys are accessible"
            echo "  4. Test SOPS manually: echo 'test: data' | sops --encrypt /dev/stdin"
            ;;
        "CONFIG")
            echo
            echo "Configuration Troubleshooting:"
            echo "  1. Check that configuration files exist and are readable"
            echo "  2. Verify file paths are correct"
            echo "  3. Ensure proper file permissions"
            echo "  4. Check configuration file syntax"
            ;;
        "SERVICE")
            echo
            echo "Service Troubleshooting:"
            echo "  1. Check systemd user service status: systemctl --user status [service-name]"
            echo "  2. Verify service files are properly installed"
            echo "  3. Ensure proper permissions for service operations"
            echo "  4. Check service logs: journalctl --user -u [service-name]"
            ;;
    esac
}

# Export functions for use by other scripts
export -f exit_with_code
export -f error_exit
export -f validate_sops_operation
export -f validate_file_operation
export -f validate_config_file
export -f validate_directory
export -f validate_service_operation
export -f format_error_message
export -f print_error_help

# Export constants
export EXIT_SUCCESS
export EXIT_GENERAL_ERROR
export EXIT_SOPS_ERROR
export EXIT_CONFIG_ERROR
export EXIT_SERVICE_ERROR