#!/bin/bash
#
# sops_utils.sh - Foundational SOPS encryption detection utilities
#
# This script provides core utilities for detecting and working with SOPS
# encrypted files in a bash-based journal management system.
#
# Functions:
#   - detect_sops_config()           Check for .sops.yaml config file
#   - check_sops_available()         Verify sops executable is available
#   - is_file_encrypted()            Detect if file has sops encryption headers
#   - detect_file_encryption_status() High-level encryption detection with prompts
#   - sops_config_exists()           Check if sops config is available
#

set -e

# Source common utilities if available
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]]; then
    # shellcheck source=common.sh
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

#
# detect_sops_config() - Check for .sops.yaml configuration file
#
# Usage: detect_sops_config [config_path]
#
# Parameters:
#   config_path (optional) - Custom path to check for sops config
#
# Returns:
#   Prints the config path if found, empty string if not found
#   Exit code: 0 if found, 1 if not found
#
detect_sops_config() {
    local config_path="${1:-}"
    local sops_config=""

    log "DEBUG" "Detecting SOPS config${config_path:+ at: $config_path}"

    if [[ -n "$config_path" ]]; then
        # Check custom config path
        if [[ -f "$config_path" ]]; then
            sops_config="$config_path"
            log "DEBUG" "Found SOPS config at custom path: $config_path"
        elif [[ -f "$config_path/.sops.yaml" ]]; then
            sops_config="$config_path/.sops.yaml"
            log "DEBUG" "Found .sops.yaml in custom directory: $config_path"
        fi
    else
        # Check current directory
        if [[ -f ".sops.yaml" ]]; then
            sops_config="./.sops.yaml"
            log "DEBUG" "Found .sops.yaml in current directory"
        elif [[ -f ".sops.yml" ]]; then
            sops_config="./.sops.yml"
            log "DEBUG" "Found .sops.yml in current directory"
        fi
    fi

    if [[ -n "$sops_config" ]]; then
        echo "$sops_config"
        return 0
    else
        log "DEBUG" "No SOPS config found"
        echo ""
        return 1
    fi
}

#
# check_sops_available() - Verify that the sops executable is available in PATH
#
# Returns:
#   0 if sops is available, 1 if not available
#
check_sops_available() {
    log "DEBUG" "Checking if SOPS is available in PATH"
    
    if command -v sops &>/dev/null; then
        local sops_version
        sops_version=$(sops --version 2>/dev/null | head -n1 || echo "unknown")
        log "DEBUG" "SOPS is available: $sops_version"
        return 0
    else
        log "WARN" "SOPS executable not found in PATH"
        return 1
    fi
}

#
# is_file_encrypted() - Detect if a file has SOPS encryption headers
#
# Usage: is_file_encrypted <file_path>
#
# Parameters:
#   file_path - Path to the file to check
#
# Returns:
#   0 if encrypted, 1 if not encrypted, 2 if file doesn't exist or can't be read
#
is_file_encrypted() {
    local file_path="$1"
    
    if [[ -z "$file_path" ]]; then
        log "ERROR" "is_file_encrypted: file_path parameter is required"
        return 2
    fi
    
    log "DEBUG" "Checking if file is encrypted: $file_path"
    
    # Check if file exists and is readable
    if [[ ! -f "$file_path" ]]; then
        log "WARN" "File does not exist: $file_path"
        return 2
    fi
    
    if [[ ! -r "$file_path" ]]; then
        log "WARN" "File is not readable: $file_path"
        return 2
    fi
    
    # Check for SOPS encryption markers in the file
    # SOPS typically adds metadata like "sops:" or "sops_version:"
    if grep -q "sops:" "$file_path" 2>/dev/null; then
        log "DEBUG" "File appears to be SOPS encrypted (found 'sops:' marker): $file_path"
        return 0
    fi
    
    if grep -q "sops_version:" "$file_path" 2>/dev/null; then
        log "DEBUG" "File appears to be SOPS encrypted (found 'sops_version:' marker): $file_path"
        return 0
    fi
    
    # Check for encrypted data patterns (base64-like strings that SOPS uses)
    if grep -q "ENC\[" "$file_path" 2>/dev/null; then
        log "DEBUG" "File appears to be SOPS encrypted (found 'ENC[' pattern): $file_path"
        return 0
    fi
    
    # Check for PGP/GPG encrypted blocks
    if grep -q "-----BEGIN PGP MESSAGE-----" "$file_path" 2>/dev/null; then
        log "DEBUG" "File appears to be PGP/GPG encrypted: $file_path"
        return 0
    fi
    
    log "DEBUG" "File does not appear to be encrypted: $file_path"
    return 1
}

#
# detect_file_encryption_status() - High-level function combining header detection with user prompts
#
# Usage: detect_file_encryption_status <file_path>
#
# Parameters:
#   file_path - Path to the file to check
#
# Returns:
#   Prints "encrypted", "unencrypted", or "error"
#   Exit code: 0 on success, 1 on error
#
detect_file_encryption_status() {
    local file_path="$1"
    
    if [[ -z "$file_path" ]]; then
        log "ERROR" "detect_file_encryption_status: file_path parameter is required"
        echo "error"
        return 1
    fi
    
    log "DEBUG" "Detecting encryption status for: $file_path"
    
    # Try automatic detection first
    local detection_result
    is_file_encrypted "$file_path"
    detection_result=$?
    
    case $detection_result in
        0)
            log "INFO" "File detected as encrypted: $file_path"
            echo "encrypted"
            return 0
            ;;
        1)
            log "INFO" "File detected as unencrypted: $file_path"
            echo "unencrypted"
            return 0
            ;;
        2)
            # File doesn't exist or can't be read - this is an error case
            log "ERROR" "Cannot read file for encryption detection: $file_path"
            echo "error"
            return 1
            ;;
        *)
            # Unknown result from is_file_encrypted - fall through to manual prompt
            log "WARN" "Automatic encryption detection failed for: $file_path"
            ;;
    esac
    
    # If automatic detection is inconclusive, prompt the user
    log "INFO" "Automatic encryption detection inconclusive, prompting user"
    
    # Use confirm_action if available from common.sh, otherwise implement inline
    if command -v confirm_action &>/dev/null; then
        if confirm_action "Is this file encrypted?" "n"; then
            echo "encrypted"
            return 0
        else
            echo "unencrypted"
            return 0
        fi
    else
        # Fallback prompt implementation
        while true; do
            read -r -p "Is this file encrypted? (y/n): " response
            case $response in
                [Yy]|[Yy][Ee][Ss])
                    echo "encrypted"
                    return 0
                    ;;
                [Nn]|[Nn][Oo])
                    echo "unencrypted"
                    return 0
                    ;;
                *)
                    echo "Please answer yes (y) or no (n)."
                    ;;
            esac
        done
    fi
}

#
# sops_config_exists() - Check if a SOPS config is available
#
# Usage: sops_config_exists [config_path]
#
# Parameters:
#   config_path (optional) - Custom path to check for sops config
#
# Returns:
#   Prints the config path if found, empty string if not found
#   Exit code: 0 if found, 1 if not found
#
sops_config_exists() {
    local config_path="${1:-}"
    
    log "DEBUG" "Checking if SOPS config exists${config_path:+ at: $config_path}"
    
    # This function is essentially an alias for detect_sops_config
    # but with clearer naming for the specific use case of existence checking
    detect_sops_config "$config_path"
}

# Initialize logging if setup_logging function is available
if command -v setup_logging &>/dev/null; then
    setup_logging
fi

log "DEBUG" "SOPS utilities loaded successfully"