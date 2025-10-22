#!/bin/bash

# Master test runner for all GameLift scripts
# This script runs all test suites for the GameLift scripts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(dirname "$0")"
TEST_SCRIPTS=(
    "test_generate_auth_token.sh"
    "test_register_compute.sh"
    "test_setup_game_server.sh"
)

# Test counters
TOTAL_TESTS_RUN=0
TOTAL_TESTS_PASSED=0
TOTAL_TESTS_FAILED=0
SCRIPTS_RUN=0
SCRIPTS_PASSED=0
SCRIPTS_FAILED=0

# Function to print colored output
print_status() {
    echo -e "${BLUE}[MASTER]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Function to run a test script
run_test_script() {
    local test_script="$1"
    local script_path="$SCRIPT_DIR/$test_script"
    
    if [[ ! -f "$script_path" ]]; then
        print_error "Test script not found: $script_path"
        return 1
    fi
    
    if [[ ! -x "$script_path" ]]; then
        print_warning "Test script is not executable, making it executable..."
        chmod +x "$script_path"
    fi
    
    print_status "Running test script: $test_script"
    echo "========================================"
    
    if "$script_path"; then
        print_success "Test script passed: $test_script"
        ((SCRIPTS_PASSED++))
        return 0
    else
        print_error "Test script failed: $test_script"
        ((SCRIPTS_FAILED++))
        return 1
    fi
}

# Function to run all test scripts
run_all_test_scripts() {
    print_status "Starting master test run for all GameLift scripts"
    echo "========================================"
    
    for test_script in "${TEST_SCRIPTS[@]}"; do
        ((SCRIPTS_RUN++))
        if run_test_script "$test_script"; then
            echo ""
        else
            echo ""
        fi
    done
    
    echo "========================================"
    print_status "Master Test Results:"
    echo "  Scripts Run: $SCRIPTS_RUN"
    echo "  Scripts Passed: $SCRIPTS_PASSED"
    echo "  Scripts Failed: $SCRIPTS_FAILED"
    
    if [[ $SCRIPTS_FAILED -eq 0 ]]; then
        print_success "All test scripts passed!"
        return 0
    else
        print_error "Some test scripts failed. Check the output above for details."
        return 1
    fi
}

# Function to run individual test script
run_individual_test() {
    local test_name="$1"
    local script_path="$SCRIPT_DIR/test_${test_name}.sh"
    
    if [[ ! -f "$script_path" ]]; then
        print_error "Test script not found: $script_path"
        print_status "Available test scripts:"
        for script in "${TEST_SCRIPTS[@]}"; do
            echo "  - ${script%.sh}"
        done
        return 1
    fi
    
    print_status "Running individual test: $test_name"
    echo "========================================"
    
    if "$script_path"; then
        print_success "Individual test passed: $test_name"
        return 0
    else
        print_error "Individual test failed: $test_name"
        return 1
    fi
}

# Function to clean up all test files
cleanup_all_test_files() {
    print_status "Cleaning up all test files..."
    
    for test_script in "${TEST_SCRIPTS[@]}"; do
        local script_path="$SCRIPT_DIR/$test_script"
        if [[ -f "$script_path" ]]; then
            "$script_path" --cleanup
        fi
    done
    
    # Clean up any remaining test output directories
    find "$SCRIPT_DIR" -name "test_output" -type d -exec rm -rf {} + 2>/dev/null || true
    
    print_success "All test files cleaned up"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [TEST_NAME]"
    echo ""
    echo "Options:"
    echo "  -h, --help               Show this help message"
    echo "  -c, --cleanup            Clean up all test files and exit"
    echo "  -v, --verbose            Show detailed test output"
    echo "  -l, --list               List available test scripts"
    echo ""
    echo "Arguments:"
    echo "  TEST_NAME                Run specific test script (generate_auth_token, register_compute, setup_game_server)"
    echo ""
    echo "Examples:"
    echo "  $0                       Run all test scripts"
    echo "  $0 generate_auth_token   Run only the generate_auth_token test"
    echo "  $0 --cleanup             Clean up all test files"
    echo "  $0 --list                List available test scripts"
    echo "  $0 --verbose             Run all tests with verbose output"
}

# Function to list available test scripts
list_test_scripts() {
    print_status "Available test scripts:"
    for script in "${TEST_SCRIPTS[@]}"; do
        local test_name="${script#test_}"
        test_name="${test_name%.sh}"
        echo "  - $test_name"
    done
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if all test scripts exist
    local missing_scripts=()
    for test_script in "${TEST_SCRIPTS[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$test_script" ]]; then
            missing_scripts+=("$test_script")
        fi
    done
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        print_error "Missing test scripts:"
        for script in "${missing_scripts[@]}"; do
            echo "  - $script"
        done
        return 1
    fi
    
    print_success "All test scripts found"
    return 0
}

# Main function
main() {
    local verbose=false
    local cleanup_only=false
    local list_only=false
    local test_name=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--cleanup)
                cleanup_only=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -l|--list)
                list_only=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$test_name" ]]; then
                    test_name="$1"
                else
                    print_error "Multiple test names specified. Please specify only one test name."
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Handle list only
    if [[ "$list_only" == "true" ]]; then
        list_test_scripts
        exit 0
    fi
    
    # Handle cleanup only
    if [[ "$cleanup_only" == "true" ]]; then
        cleanup_all_test_files
        exit 0
    fi
    
    # Set up cleanup trap
    trap cleanup_all_test_files EXIT
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Run tests
    if [[ -n "$test_name" ]]; then
        # Run individual test
        if run_individual_test "$test_name"; then
            exit 0
        else
            exit 1
        fi
    else
        # Run all tests
        if run_all_test_scripts; then
            exit 0
        else
            exit 1
        fi
    fi
}

# Run main function
main "$@"
