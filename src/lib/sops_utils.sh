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
# check_sops_availability_with_guidance() - Enhanced sops availability check with user guidance
#
# Provides detailed error messages and installation guidance when sops is not available
# Also checks version compatibility and provides warnings for old versions
#
# Usage: check_sops_availability_with_guidance
#
# Returns:
#   0 if sops is available and compatible, 1 if not available or incompatible
#   Sets global variables: SOPS_EXECUTABLE_AVAILABLE, SOPS_VERSION
#
check_sops_availability_with_guidance() {
    local sops_version_output
    
    log "DEBUG" "Performing enhanced SOPS availability check"
    
    if ! command -v sops >/dev/null 2>&1; then
        log "ERROR" "SOPS executable not found in PATH"
        
        # Provide helpful installation guidance based on platform
        if command -v brew >/dev/null 2>&1; then
            log "ERROR" "Error: sops command not found. Install with: brew install sops"
        elif command -v apt-get >/dev/null 2>&1; then
            log "ERROR" "Error: sops command not found. Install with: sudo apt-get install sops"
        elif command -v yum >/dev/null 2>&1; then
            log "ERROR" "Error: sops command not found. Install with: sudo yum install sops"
        elif command -v pacman >/dev/null 2>&1; then
            log "ERROR" "Error: sops command not found. Install with: sudo pacman -S sops"
        else
            log "ERROR" "Error: sops command not found. Please install sops from: https://github.com/mozilla/sops"
        fi
        
        SOPS_EXECUTABLE_AVAILABLE=false
        SOPS_VERSION=""
        return 1
    fi
    
    SOPS_EXECUTABLE_AVAILABLE=true
    
    # Get version information
    if sops_version_output=$(sops --version 2>/dev/null | head -n1); then
        SOPS_VERSION="$sops_version_output"
        log "DEBUG" "SOPS available: $SOPS_VERSION"
    else
        log "WARN" "SOPS executable found but version check failed"
        SOPS_VERSION="unknown"
    fi
    
    # Check version compatibility (version 3.0.0+ is recommended)
    local version_number
    version_number=$(echo "$SOPS_VERSION" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "0.0.0")
    
    if [[ "$version_number" != "0.0.0" ]]; then
        local major minor patch
        IFS='.' read -r major minor patch <<< "$version_number"
        if [[ $major -lt 3 ]]; then
            log "WARN" "Warning: SOPS version $version_number is older than recommended (3.0.0+). Some features may not work correctly."
            log "WARN" "Consider updating SOPS to the latest version for optimal compatibility."
        elif [[ $major -eq 3 && $minor -eq 0 && $patch -lt 5 ]]; then
            log "INFO" "SOPS version $version_number detected. Consider updating to 3.0.5+ for latest bug fixes."
        fi
    fi
    
    return 0
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

# Global variables for sops state (set by check_sops_availability_with_guidance)
SOPS_EXECUTABLE_AVAILABLE=false
SOPS_VERSION=""

#
# validate_sops_config() - Validate SOPS configuration file format and content
#
# Usage: validate_sops_config <config_path>
#
# Parameters:
#   config_path - Path to the SOPS configuration file
#
# Returns:
#   0 if config is valid, 1 if invalid
#
validate_sops_config() {
    local config_path="$1"
    
    if [[ -z "$config_path" ]]; then
        log "ERROR" "validate_sops_config: config_path parameter is required"
        return 1
    fi
    
    log "DEBUG" "Validating SOPS config: $config_path"
    
    # Check if file exists and is readable
    if [[ ! -f "$config_path" ]]; then
        log "ERROR" "SOPS config file not found: $config_path"
        return 1
    fi
    
    if [[ ! -r "$config_path" ]]; then
        log "ERROR" "SOPS config file is not readable: $config_path"
        return 1
    fi
    
    # Check if file is empty
    if [[ ! -s "$config_path" ]]; then
        log "ERROR" "SOPS config file is empty: $config_path"
        return 1
    fi
    
    # Validate YAML format (basic check)
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$config_path'))" 2>/dev/null; then
            log "ERROR" "SOPS config file contains invalid YAML syntax: $config_path"
            return 1
        fi
    elif command -v yq >/dev/null 2>&1; then
        if ! yq eval '.' "$config_path" >/dev/null 2>&1; then
            log "ERROR" "SOPS config file contains invalid YAML syntax: $config_path"
            return 1
        fi
    else
        # Basic YAML syntax check without external tools
        if grep -q $'^\t' "$config_path"; then
            log "WARN" "SOPS config contains tabs - YAML should use spaces for indentation: $config_path"
        fi
    fi
    
    # Check for required sections
    local has_creation_rules=false
    local has_keys=false
    
    if grep -q "creation_rules:" "$config_path" 2>/dev/null; then
        has_creation_rules=true
        log "DEBUG" "Found creation_rules section in SOPS config"
    fi
    
    # Check for key configurations (PGP, KMS, etc.)
    if grep -qE "(pgp|kms|age|azure_kv|hc_vault|gcp_kms):" "$config_path" 2>/dev/null; then
        has_keys=true
        log "DEBUG" "Found key configuration in SOPS config"
    fi
    
    if [[ "$has_creation_rules" == "false" ]]; then
        log "WARN" "SOPS config appears to be missing creation_rules section: $config_path"
        log "WARN" "This may prevent automatic encryption of new files"
    fi
    
    if [[ "$has_keys" == "false" ]]; then
        log "ERROR" "SOPS config appears to be missing key configuration (pgp, kms, age, etc.): $config_path"
        log "ERROR" "At least one key type must be configured for encryption to work"
        return 1
    fi
    
    log "DEBUG" "SOPS config validation passed: $config_path"
    return 0
}

#
# test_sops_encryption() - Test SOPS encryption/decryption functionality
#
# Usage: test_sops_encryption [config_path]
#
# Parameters:
#   config_path (optional) - Path to SOPS config file to test with
#
# Returns:
#   0 if encryption test succeeds, 1 if it fails
#
test_sops_encryption() {
    local config_path="${1:-}"
    local temp_file temp_encrypted_file
    
    log "DEBUG" "Testing SOPS encryption functionality"
    
    # Create temporary test file
    temp_file=$(mktemp) || {
        log "ERROR" "Failed to create temporary file for SOPS test"
        return 1
    }
    
    temp_encrypted_file="${temp_file}.enc"
    
    # Cleanup function
    cleanup_test_files() {
        rm -f "$temp_file" "$temp_encrypted_file" 2>/dev/null
    }
    
    # Set trap for cleanup
    trap cleanup_test_files EXIT
    
    # Write test content
    echo "test_data: hello_world" > "$temp_file" || {
        log "ERROR" "Failed to write test data"
        cleanup_test_files
        return 1
    }
    
    # Test encryption
    local sops_cmd="sops --encrypt"
    if [[ -n "$config_path" ]]; then
        sops_cmd="$sops_cmd --config '$config_path'"
    fi
    sops_cmd="$sops_cmd '$temp_file'"
    
    if ! eval "$sops_cmd" > "$temp_encrypted_file" 2>/dev/null; then
        log "ERROR" "SOPS encryption test failed - unable to encrypt test file"
        log "ERROR" "This may indicate missing or invalid encryption keys"
        cleanup_test_files
        return 1
    fi
    
    # Verify encrypted file contains SOPS metadata
    if ! grep -q "sops:" "$temp_encrypted_file" 2>/dev/null; then
        log "ERROR" "SOPS encryption test failed - encrypted file missing SOPS metadata"
        cleanup_test_files
        return 1
    fi
    
    # Test decryption
    local decrypted_content
    if ! decrypted_content=$(sops --decrypt "$temp_encrypted_file" 2>/dev/null); then
        log "ERROR" "SOPS decryption test failed - unable to decrypt test file"
        log "ERROR" "This may indicate issues with key access or configuration"
        cleanup_test_files
        return 1
    fi
    
    # Verify decrypted content matches original
    if [[ "$decrypted_content" != "test_data: hello_world" ]]; then
        log "ERROR" "SOPS encryption test failed - decrypted content doesn't match original"
        cleanup_test_files
        return 1
    fi
    
    log "DEBUG" "SOPS encryption test passed successfully"
    cleanup_test_files
    return 0
}

#
# get_sops_error_guidance() - Provide user-friendly guidance for common SOPS errors
#
# Usage: get_sops_error_guidance <error_output>
#
# Parameters:
#   error_output - Error message from SOPS command
#
# Returns:
#   Prints helpful guidance message using print function if available, otherwise log
#
get_sops_error_guidance() {
    local error_output="$1"
    
    if [[ -z "$error_output" ]]; then
        return 0
    fi
    
    # Use print function if available (from main script), otherwise use log
    local print_func="log"
    if type -t print >/dev/null 2>&1; then
        print_func="print"
    fi
    
    # Common error patterns and guidance
    if echo "$error_output" | grep -qi "no key could decrypt"; then
        $print_func "Decryption failed: No accessible encryption keys found" "ERROR"
        $print_func "Troubleshooting steps:" "ERROR"
        $print_func "  1. Verify you have access to the encryption keys (PGP/Age private key, KMS permissions, etc.)" "ERROR"
        $print_func "  2. Check if the file was encrypted with different keys than configured" "ERROR"
        $print_func "  3. Ensure your key is properly imported and accessible" "ERROR"
    elif echo "$error_output" | grep -qi "failed to get data key"; then
        $print_func "Key access failed: Unable to retrieve decryption key" "ERROR"
        $print_func "Troubleshooting steps:" "ERROR"
        $print_func "  1. For KMS: Check AWS credentials and KMS key permissions" "ERROR"
        $print_func "  2. For PGP: Verify your private key is imported and accessible" "ERROR"
        $print_func "  3. Check network connectivity if using cloud key services" "ERROR"
    elif echo "$error_output" | grep -qi "no creation rule"; then
        $print_func "Encryption failed: No matching creation rule in SOPS config" "ERROR"
        $print_func "Troubleshooting steps:" "ERROR"
        $print_func "  1. Check your .sops.yaml creation_rules section" "ERROR"
        $print_func "  2. Ensure file path/extension matches a creation rule pattern" "ERROR"
        $print_func "  3. Add a creation rule for your file type if needed" "ERROR"
    elif echo "$error_output" | grep -qi "config file not found"; then
        $print_func "Configuration error: SOPS config file not found" "ERROR"
        $print_func "Troubleshooting steps:" "ERROR"
        $print_func "  1. Create a .sops.yaml file in your project root" "ERROR"
        $print_func "  2. Or specify config path with --config option" "ERROR"
        $print_func "  3. See https://github.com/mozilla/sops#usage for config examples" "ERROR"
    elif echo "$error_output" | grep -qi "permission denied"; then
        $print_func "File access error: Permission denied" "ERROR"
        $print_func "Troubleshooting steps:" "ERROR"
        $print_func "  1. Check file and directory permissions" "ERROR"
        $print_func "  2. Ensure you have write access to the target location" "ERROR"
        $print_func "  3. Verify the file is not locked by another process" "ERROR"
    else
        # Generic guidance for unrecognized errors
        $print_func "SOPS operation failed with error:" "ERROR"
        $print_func "  $error_output" "ERROR"
        $print_func "General troubleshooting steps:" "ERROR"
        $print_func "  1. Check SOPS configuration (.sops.yaml)" "ERROR"
        $print_func "  2. Verify key access and permissions" "ERROR"
        $print_func "  3. Test with a simple file first" "ERROR"
        $print_func "  4. Check SOPS documentation: https://github.com/mozilla/sops" "ERROR"
    fi
}

log "DEBUG" "SOPS utilities loaded successfully"