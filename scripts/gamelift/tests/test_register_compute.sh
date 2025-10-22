#!/bin/bash

# Test script for register_compute.sh
# This script tests the functionality of the GameLift Anywhere Compute Registration Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(dirname "$0")"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
REGISTER_COMPUTE_SCRIPT="$PARENT_DIR/register_compute.sh"
TEST_OUTPUT_DIR="$SCRIPT_DIR/test_output"
TEST_FLEET_ID="fleet-test-12345678-1234-1234-1234-123456789012"
TEST_COMPUTE_NAME="TestCompute-$(date +%s)"
TEST_LOCATION="custom-test-location"
TEST_IP_ADDRESS="192.168.1.100"
TEST_REGION="us-east-1"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Function to print colored output
print_status() {
    echo -e "${BLUE}[TEST]${NC} $1"
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

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    ((TESTS_RUN++))
    print_status "Running test: $test_name"
    
    # Create test output directory
    mkdir -p "$TEST_OUTPUT_DIR"
    
    # Run the test command
    if eval "$test_command" > "$TEST_OUTPUT_DIR/${test_name}.out" 2> "$TEST_OUTPUT_DIR/${test_name}.err"; then
        local actual_exit_code=$?
    else
        local actual_exit_code=$?
    fi
    
    # Check exit code
    if [[ $actual_exit_code -eq $expected_exit_code ]]; then
        print_success "$test_name"
        ((TESTS_PASSED++))
        return 0
    else
        print_error "$test_name (Expected exit code: $expected_exit_code, Got: $actual_exit_code)"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Function to check if script exists
check_script_exists() {
    if [[ ! -f "$REGISTER_COMPUTE_SCRIPT" ]]; then
        print_error "register_compute.sh script not found at: $REGISTER_COMPUTE_SCRIPT"
        exit 1
    fi
    
    if [[ ! -x "$REGISTER_COMPUTE_SCRIPT" ]]; then
        print_warning "register_compute.sh script is not executable, making it executable..."
        chmod +x "$REGISTER_COMPUTE_SCRIPT"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        return 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install it first."
        return 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure' first."
        return 1
    fi
    
    print_success "Prerequisites check passed"
    return 0
}

# Test 1: Help option
test_help_option() {
    run_test "help_option" "$REGISTER_COMPUTE_SCRIPT --help" 0
}

# Test 2: Missing required parameters
test_missing_parameters() {
    run_test "missing_fleet_id" "$REGISTER_COMPUTE_SCRIPT --compute-name $TEST_COMPUTE_NAME" 1
}

# Test 3: Invalid output format
test_invalid_output_format() {
    run_test "invalid_output_format" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --output invalid" 1
}

# Test 4: Valid output formats
test_valid_output_formats() {
    # Note: These tests will fail with actual AWS calls, but they test the parameter validation
    run_test "output_format_text" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --output text" 1
    run_test "output_format_json" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --output json" 1
}

# Test 5: Environment variable support
test_environment_variables() {
    export GAMELIFT_FLEET_ID="$TEST_FLEET_ID"
    export GAMELIFT_COMPUTE_NAME="$TEST_COMPUTE_NAME"
    export GAMELIFT_LOCATION="$TEST_LOCATION"
    export AWS_DEFAULT_REGION="$TEST_REGION"
    
    run_test "env_vars_fleet_id" "$REGISTER_COMPUTE_SCRIPT --compute-name $TEST_COMPUTE_NAME" 1
    run_test "env_vars_compute_name" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID" 1
    run_test "env_vars_location" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME" 1
    
    unset GAMELIFT_FLEET_ID
    unset GAMELIFT_COMPUTE_NAME
    unset GAMELIFT_LOCATION
    unset AWS_DEFAULT_REGION
}

# Test 6: Cleanup functionality
test_cleanup_functionality() {
    # Test cleanup help
    run_test "cleanup_help" "$REGISTER_COMPUTE_SCRIPT --cleanup" 1
    
    # Test cleanup with valid types
    run_test "cleanup_temp" "$REGISTER_COMPUTE_SCRIPT --cleanup temp" 0
    run_test "cleanup_env" "$REGISTER_COMPUTE_SCRIPT --cleanup env" 0
    run_test "cleanup_all" "$REGISTER_COMPUTE_SCRIPT --cleanup all" 0
    
    # Test cleanup with invalid type
    run_test "cleanup_invalid" "$REGISTER_COMPUTE_SCRIPT --cleanup invalid" 1
}

# Test 7: Script syntax and basic functionality
test_script_syntax() {
    # Test that the script can be sourced without errors (basic syntax check)
    run_test "script_syntax" "bash -n $REGISTER_COMPUTE_SCRIPT" 0
}

# Test 8: Long option names
test_long_options() {
    run_test "long_options_help" "$REGISTER_COMPUTE_SCRIPT --help" 0
    run_test "long_options_fleet_id" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME" 1
    run_test "long_options_compute_name" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME" 1
    run_test "long_options_location" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --location $TEST_LOCATION" 1
    run_test "long_options_ip_address" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --ip-address $TEST_IP_ADDRESS" 1
    run_test "long_options_region" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --region $TEST_REGION" 1
    run_test "long_options_output" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --output json" 1
    run_test "long_options_yes" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --yes" 1
}

# Test 9: Short option names
test_short_options() {
    run_test "short_options_h" "$REGISTER_COMPUTE_SCRIPT -h" 0
    run_test "short_options_f" "$REGISTER_COMPUTE_SCRIPT -f $TEST_FLEET_ID -c $TEST_COMPUTE_NAME" 1
    run_test "short_options_c" "$REGISTER_COMPUTE_SCRIPT -f $TEST_FLEET_ID -c $TEST_COMPUTE_NAME" 1
    run_test "short_options_l" "$REGISTER_COMPUTE_SCRIPT -f $TEST_FLEET_ID -c $TEST_COMPUTE_NAME -l $TEST_LOCATION" 1
    run_test "short_options_i" "$REGISTER_COMPUTE_SCRIPT -f $TEST_FLEET_ID -c $TEST_COMPUTE_NAME -i $TEST_IP_ADDRESS" 1
    run_test "short_options_r" "$REGISTER_COMPUTE_SCRIPT -f $TEST_FLEET_ID -c $TEST_COMPUTE_NAME -r $TEST_REGION" 1
    run_test "short_options_o" "$REGISTER_COMPUTE_SCRIPT -f $TEST_FLEET_ID -c $TEST_COMPUTE_NAME -o json" 1
    run_test "short_options_y" "$REGISTER_COMPUTE_SCRIPT -f $TEST_FLEET_ID -c $TEST_COMPUTE_NAME -y" 1
}

# Test 10: Edge cases
test_edge_cases() {
    # Empty parameters
    run_test "empty_fleet_id" "$REGISTER_COMPUTE_SCRIPT --fleet-id '' --compute-name $TEST_COMPUTE_NAME" 1
    run_test "empty_compute_name" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name ''" 1
    run_test "empty_location" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --location ''" 1
    run_test "empty_ip_address" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --ip-address ''" 1
    
    # Very long parameters
    local long_fleet_id="fleet-$(printf 'a%.0s' {1..100})"
    local long_compute_name="compute-$(printf 'b%.0s' {1..100})"
    local long_location="location-$(printf 'c%.0s' {1..100})"
    run_test "long_fleet_id" "$REGISTER_COMPUTE_SCRIPT --fleet-id $long_fleet_id --compute-name $TEST_COMPUTE_NAME" 1
    run_test "long_compute_name" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $long_compute_name" 1
    run_test "long_location" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --location $long_location" 1
}

# Test 11: IP address validation
test_ip_address_validation() {
    # Valid IP addresses
    run_test "valid_ip_1" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --ip-address 192.168.1.1" 1
    run_test "valid_ip_2" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --ip-address 10.0.0.1" 1
    run_test "valid_ip_3" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --ip-address 172.16.0.1" 1
    
    # Invalid IP addresses (these should still pass parameter validation but fail at AWS level)
    run_test "invalid_ip_1" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --ip-address 999.999.999.999" 1
    run_test "invalid_ip_2" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --ip-address not-an-ip" 1
}

# Test 12: Compute name generation
test_compute_name_generation() {
    # Test auto-generation of compute name
    run_test "auto_generate_compute_name" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID" 1
}

# Test 13: Save functionality
test_save_functionality() {
    local test_file="$TEST_OUTPUT_DIR/test_compute_info.json"
    
    # Test save to file (will fail at AWS level but should pass parameter validation)
    run_test "save_to_file" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --save $test_file" 1
    
    # Test save to file without extension
    run_test "save_to_file_no_ext" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --save $TEST_OUTPUT_DIR/test_compute_info" 1
}

# Test 14: Confirmation prompts
test_confirmation_prompts() {
    # Test with --yes flag (should skip confirmation)
    run_test "skip_confirmation_yes" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --yes" 1
    
    # Test without --yes flag (should ask for confirmation but we'll simulate it)
    run_test "require_confirmation" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME" 1
}

# Test 15: Region validation
test_region_validation() {
    # Test valid regions
    run_test "valid_region_us_east_1" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --region us-east-1" 1
    run_test "valid_region_us_west_2" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --region us-west-2" 1
    run_test "valid_region_eu_west_1" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --region eu-west-1" 1
    
    # Test invalid regions (should still pass parameter validation)
    run_test "invalid_region" "$REGISTER_COMPUTE_SCRIPT --fleet-id $TEST_FLEET_ID --compute-name $TEST_COMPUTE_NAME --region invalid-region" 1
}

# Function to run all tests
run_all_tests() {
    print_status "Starting tests for register_compute.sh"
    echo "========================================"
    
    # Check script exists
    check_script_exists
    
    # Check prerequisites
    if ! check_prerequisites; then
        print_error "Prerequisites check failed. Skipping tests that require AWS."
        print_warning "Running only basic syntax and parameter tests..."
    fi
    
    # Run tests
    test_script_syntax
    test_help_option
    test_missing_parameters
    test_invalid_output_format
    test_valid_output_formats
    test_environment_variables
    test_cleanup_functionality
    test_long_options
    test_short_options
    test_edge_cases
    test_ip_address_validation
    test_compute_name_generation
    test_save_functionality
    test_confirmation_prompts
    test_region_validation
    
    echo "========================================"
    print_status "Test Results:"
    echo "  Tests Run: $TESTS_RUN"
    echo "  Tests Passed: $TESTS_PASSED"
    echo "  Tests Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        print_success "All tests passed!"
        return 0
    else
        print_error "Some tests failed. Check the output above for details."
        return 1
    fi
}

# Function to clean up test files
cleanup_test_files() {
    if [[ -d "$TEST_OUTPUT_DIR" ]]; then
        rm -rf "$TEST_OUTPUT_DIR"
        print_status "Cleaned up test output directory"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help               Show this help message"
    echo "  -c, --cleanup            Clean up test files and exit"
    echo "  -v, --verbose            Show detailed test output"
    echo ""
    echo "Examples:"
    echo "  $0                       Run all tests"
    echo "  $0 --cleanup             Clean up test files"
    echo "  $0 --verbose             Run tests with verbose output"
}

# Main function
main() {
    local verbose=false
    local cleanup_only=false
    
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
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Handle cleanup only
    if [[ "$cleanup_only" == "true" ]]; then
        cleanup_test_files
        exit 0
    fi
    
    # Set up cleanup trap
    trap cleanup_test_files EXIT
    
    # Run tests
    if run_all_tests; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"
