#!/usr/bin/env bash
#
# run_tests.sh - Test runner for journal management system
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SOPS_TEST_SCRIPT="${SCRIPT_DIR}/test_sops_integration.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

# Check prerequisites
check_prerequisites() {
    local missing_deps=()

    if ! command -v sops >/dev/null 2>&1; then
        missing_deps+=("sops")
    fi

    if ! command -v age-keygen >/dev/null 2>&1; then
        missing_deps+=("age")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies and try again."
        echo
        echo "Installation guides:"
        echo "  SOPS: https://github.com/getsops/sops"
        echo "  Age:  https://github.com/FiloSottile/age"
        return 1
    fi

    return 0
}

# Run all tests
run_all_tests() {
    local exit_code=0

    print_info "Running SOPS integration tests..."
    if ! "$SOPS_TEST_SCRIPT"; then
        exit_code=1
    fi

    echo
    if [[ $exit_code -eq 0 ]]; then
        print_success "All test suites passed!"
    else
        print_error "Some tests failed!"
    fi

    return $exit_code
}

# Main execution
main() {
    echo "=========================================="
    echo "    JOURNAL MANAGEMENT TEST RUNNER"
    echo "=========================================="
    echo

    if ! check_prerequisites; then
        return 1
    fi

    run_all_tests
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi