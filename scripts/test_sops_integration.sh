#!/usr/bin/env bash
#
# test_sops_integration.sh - Comprehensive integration tests for SOPS encryption
#
# This script provides comprehensive testing for the journal system's SOPS
# encryption integration, covering end-to-end workflows, edge cases, and
# error conditions.
#

# set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEST_DIR="/tmp/journal_test_$$"
TEST_JOURNAL_DIR="${TEST_DIR}/journal"
TEST_KEY_FILE="${TEST_DIR}/age_key.txt"
TEST_SOPS_CONFIG="${TEST_JOURNAL_DIR}/.sops.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)"
CJ_SCRIPT="${PROJECT_ROOT}/src/bin/create_journal_entry.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

pass_test() {
    local test_name="$1"
    ((TESTS_PASSED++))
    print_success "$test_name"
}

fail_test() {
    local test_name="$1"
    local error_msg="$2"
    ((TESTS_FAILED++))
    print_error "$test_name"
    [[ -n "$error_msg" ]] && echo "    Error: $error_msg"
}

run_test() {
    local test_name="$1"
    local test_func="$2"
    ((TESTS_RUN++))

    print_info "Running: $test_name"
    if "$test_func"; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Test function returned non-zero exit code"
    fi
    echo
}

setup_test_env() {
    print_info "Setting up test environment..."

    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_JOURNAL_DIR"

    if ! command -v age-keygen >/dev/null 2>&1; then
        print_error "age-keygen is required for testing but not found in PATH"
        exit 1
    fi

    if ! command -v sops >/dev/null 2>&1; then
        print_error "sops is required for testing but not found in PATH"
        exit 1
    fi

    age-keygen -o "$TEST_KEY_FILE" >/dev/null 2>&1

    TEST_PUBLIC_KEY=$(grep "# public key:" "$TEST_KEY_FILE" | cut -d' ' -f4)

    export SOPS_AGE_KEY_FILE="$TEST_KEY_FILE"
    export EDITOR="true" # Non-interactive editor for tests

    print_success "Test environment setup complete"
    print_info "Test directory: $TEST_DIR"
    print_info "Age public key: $TEST_PUBLIC_KEY"
    echo
}

create_test_sops_config() {
    cat > "$TEST_SOPS_CONFIG" << EOF
creation_rules:
  - path_regex: \.md$
    age: >-
      $TEST_PUBLIC_KEY
EOF
}

test_sops_detection() {
    cd "$TEST_JOURNAL_DIR"

    # Test without .sops.yaml (should work in unencrypted mode)
    if ! "$CJ_SCRIPT" -q -d "$TEST_JOURNAL_DIR" >/dev/null 2>&1; then
        return 1
    fi

    # Verify unencrypted file was created
    local today_file
    today_file="journal.daily.$(date +%Y.%m.%d).md"
    if [[ ! -f "$today_file" ]]; then
        return 1
    fi

    # Verify it's not encrypted
    if grep -q '"sops":' "$today_file"; then
        return 1
    fi

    rm -f "$today_file"
    return 0
}

test_sops_config_detection() {
    cd "$TEST_JOURNAL_DIR"

    create_test_sops_config

    local output
    output=$("$CJ_SCRIPT" --verbose -d "$TEST_JOURNAL_DIR" 2>&1)

    if ! echo "$output" | grep -qE "(Using SOPS config|Found SOPS config|Found \.sops\.yaml)"; then
        echo "SOPS config not detected: $output"
        return 1
    fi

    return 0
}

test_automatic_encryption() {
    cd "$TEST_JOURNAL_DIR"

    create_test_sops_config

    # Create entry (should be automatically encrypted)
    if ! "$CJ_SCRIPT" -q -d "$TEST_JOURNAL_DIR" >/dev/null 2>&1; then
        return 1
    fi

    # Verify encrypted file was created
    local today_file
    today_file="journal.daily.$(date +%Y.%m.%d).md"
    if [[ ! -f "$today_file" ]]; then
        return 1
    fi

    # Verify it's encrypted (contains sops metadata)
    if ! grep -q '"sops":' "$today_file"; then
        echo "File was not encrypted"
        return 1
    fi

    # Verify we can decrypt it
    if ! sops --decrypt "$today_file" >/dev/null 2>&1; then
        echo "Could not decrypt created file"
        return 1
    fi

    return 0
}

test_custom_sops_config() {
    cd "$TEST_JOURNAL_DIR"

    local custom_config="${TEST_DIR}/custom.sops.yaml"
    cat > "$custom_config" << EOF
creation_rules:
  - path_regex: \.md$
    age: >-
      $TEST_PUBLIC_KEY
EOF

    # Remove default config to ensure we're using custom
    rm -f "$TEST_SOPS_CONFIG"

    # Create entry with custom config
    if ! "$CJ_SCRIPT" --sops-config "$custom_config" -q -d "$TEST_JOURNAL_DIR" >/dev/null 2>&1; then
        echo "Failed to create entry with custom SOPS config"
        return 1
    fi

    # Verify file is encrypted
    local today_file
    today_file="journal.daily.$(date +%Y.%m.%d).md"
    if [[ ! -f "$today_file" ]] || ! grep -q '"sops":' "$today_file"; then
        echo "File was not encrypted using custom SOPS config"
        return 1
    fi

    return 0
}

test_migration_workflow() {
    cd "$TEST_JOURNAL_DIR"

    # Create some unencrypted entries first
    rm -f .sops.yaml

    for i in {1..3}; do
        local date_str="2024-01-0${i}"
        local filename="journal.daily.${date_str//-/.}.md"
        echo "---
title: Test Entry $i
---
This is test content for entry $i" > "$filename"
    done

    # Now add sops config and migrate
    create_test_sops_config

    # Run migration
    if ! "$CJ_SCRIPT" --migrate-to-encrypted -d "$TEST_JOURNAL_DIR" -q >/dev/null 2>&1; then
        return 1
    fi

    # Verify all files are now encrypted
    for i in {1..3}; do
        local date_str="2024-01-0${i}"
        local filename="journal.daily.${date_str//-/.}.md"
        if [[ ! -f "$filename" ]] || ! grep -q '"sops":' "$filename"; then
            echo "File $filename was not encrypted during migration"
            return 1
        fi

        # Verify content is still accessible
        if ! sops --decrypt "$filename" | grep -q "This is test content for entry $i"; then
            echo "Content verification failed for $filename"
            return 1
        fi
    done

    return 0
}

test_invalid_sops_config() {
    cd "$TEST_JOURNAL_DIR"

    # Create invalid sops config
    cat > "$TEST_SOPS_CONFIG" << EOF
creation_rules:
  - path_regex: \.md$
    age: >-
      invalid_key_format
EOF

    # Attempt to create entry (should fail gracefully)
    local output
    output=$("$CJ_SCRIPT" -d "$TEST_JOURNAL_DIR" 2>&1)
    local exit_code=$?

    # Should fail but with informative error message
    if [[ $exit_code -eq 0 ]]; then
        echo "Expected failure with invalid config but command succeeded"
        return 1
    fi

    if ! echo "$output" | grep -iq "error\|fail"; then
        echo "Expected error message not found in output: $output"
        return 1
    fi

    return 0
}

test_edit_encrypted_entries() {
    cd "$TEST_JOURNAL_DIR"

    create_test_sops_config

    # Create an encrypted entry
    local test_date="2024-01-15"
    local filename="journal.daily.${test_date//-/.}.md"

    if ! "$CJ_SCRIPT" --date "$test_date" -q -d "$TEST_JOURNAL_DIR" >/dev/null 2>&1; then
        return 1
    fi

    # Verify file exists and is encrypted
    if [[ ! -f "$filename" ]] || ! grep -q '"sops":' "$filename"; then
        echo "Initial encrypted file creation failed"
        return 1
    fi

    # Test editing (using true as editor to avoid interactive prompt)
    export EDITOR="true"
    if ! "$CJ_SCRIPT" --date "$test_date" -e -q -d "$TEST_JOURNAL_DIR" >/dev/null 2>&1; then
        echo "Edit command failed"
        return 1
    fi

    # File should still be encrypted
    if ! grep -q '"sops":' "$filename"; then
        echo "File lost encryption after edit"
        return 1
    fi

    return 0
}

test_mixed_environment() {
    cd "$TEST_JOURNAL_DIR"

    # Create some unencrypted entries first
    for i in {1..2}; do
        local date_str="2024-01-0${i}"
        local filename="journal.daily.${date_str//-/.}.md"
        echo "---
title: Unencrypted Entry $i
---
This is unencrypted content" > "$filename"
    done

    # Add sops config
    create_test_sops_config

    # Create new entries (should be encrypted)
    for i in {3..4}; do
        local date_str="2024-01-0${i}"
        if ! "$CJ_SCRIPT" --date "$date_str" -q -d "$TEST_JOURNAL_DIR" >/dev/null 2>&1; then
            return 1
        fi
    done

    # Verify mixed state
    for i in {1..2}; do
        local filename="journal.daily.2024.01.0${i}.md"
        if [[ ! -f "$filename" ]] || grep -q '"sops":' "$filename"; then
            echo "Unencrypted file $filename was affected"
            return 1
        fi
    done

    for i in {3..4}; do
        local filename="journal.daily.2024.01.0${i}.md"
        if [[ ! -f "$filename" ]] || ! grep -q '"sops":' "$filename"; then
            echo "New file $filename was not encrypted"
            return 1
        fi
    done

    return 0
}

test_service_integration() {
    cd "$TEST_JOURNAL_DIR"

    create_test_sops_config

    # Test timestamp monitor script exists and can handle encrypted files
    local monitor_script="${PROJECT_ROOT}/src/bin/journal_timestamp_monitor.sh"
    if [[ ! -f "$monitor_script" ]]; then
        echo "Monitor script not found"
        return 1
    fi

    # Create an encrypted entry
    if ! "$CJ_SCRIPT" -q -d "$TEST_JOURNAL_DIR" >/dev/null 2>&1; then
        echo "Failed to create initial encrypted entry"
        return 1
    fi

    # Basic test that monitor script can start without error
    # (We can't test full functionality without running the service)
    timeout 2s "$monitor_script" "$TEST_JOURNAL_DIR" >/dev/null 2>&1
    local exit_code=$?
    if [[ $exit_code -ne 124 ]]; then  # 124 is timeout exit code (expected)
        echo "Monitor script failed with exit code: $exit_code"
        return 1
    fi

    return 0
}

test_atomic_operations() {
    cd "$TEST_JOURNAL_DIR"

    create_test_sops_config

    local test_date="2024-01-20"  # Use different date to avoid conflicts with other tests
    local filename="journal.daily.${test_date//-/.}.md"
    
    # Clean up any existing file from previous tests
    rm -f "$filename" 2>/dev/null

    # Create a scenario where encryption might fail (temporarily break sops config)
    cp "$TEST_SOPS_CONFIG" "${TEST_SOPS_CONFIG}.backup"
    echo "invalid yaml content" > "$TEST_SOPS_CONFIG"

    # Attempt to create entry (should fail)
    local script_output
    script_output=$("$CJ_SCRIPT" --date "$test_date" -q -d "$TEST_JOURNAL_DIR" 2>&1)
    local script_exit_code=$?
    
    if [[ $script_exit_code -eq 0 ]]; then
        echo "Expected failure but command succeeded"
        echo "Script output was: $script_output"
        return 1
    fi

    # Verify no partial file was left
    if [[ -f "$filename" ]]; then
        echo "Partial file was left after failed operation"
        echo "Script exit code: $script_exit_code"
        echo "Script output: $script_output"
        echo "File contents:"
        cat "$filename" || true
        return 1
    fi

    # Restore config and try again (should work)
    mv "${TEST_SOPS_CONFIG}.backup" "$TEST_SOPS_CONFIG"

    if ! "$CJ_SCRIPT" --date "$test_date" -q -d "$TEST_JOURNAL_DIR" >/dev/null 2>&1; then
        echo "Recovery attempt failed"
        return 1
    fi

    # Verify file exists and is encrypted
    if [[ ! -f "$filename" ]] || ! grep -q '"sops":' "$filename"; then
        echo "Recovery did not create encrypted file properly"
        return 1
    fi

    return 0
}

cleanup_test_env() {
    print_info "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
    unset SOPS_AGE_KEY_FILE
    print_success "Cleanup complete"
}

print_test_summary() {
    echo
    echo "=========================================="
    echo "           TEST RESULTS SUMMARY"
    echo "=========================================="
    echo "Tests Run:    $TESTS_RUN"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo

    if [[ $TESTS_FAILED -eq 0 ]]; then
        print_success "All tests passed!"
        return 0
    else
        print_error "Some tests failed!"
        return 1
    fi
}

main() {
    echo "=========================================="
    echo "      SOPS INTEGRATION TEST SUITE"
    echo "=========================================="
    echo

    setup_test_env

    print_info "Starting test execution..."

    run_test "SOPS Detection (Fallback Mode)" test_sops_detection
    run_test "SOPS Configuration Detection" test_sops_config_detection
    run_test "Automatic Encryption" test_automatic_encryption
    run_test "Custom SOPS Config Path" test_custom_sops_config
    run_test "Migration Workflow" test_migration_workflow
    run_test "Invalid Config Error Handling" test_invalid_sops_config
    run_test "Edit Encrypted Entries" test_edit_encrypted_entries
    run_test "Mixed Environment Support" test_mixed_environment
    run_test "Service Integration" test_service_integration
    run_test "Atomic Operations" test_atomic_operations

    cleanup_test_env
    print_test_summary

    return $?
}

# Allow script to be sourced for individual test functions
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi