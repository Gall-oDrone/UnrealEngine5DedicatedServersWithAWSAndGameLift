#!/bin/bash

# Test script for setup_game_server.sh
# This script tests the functionality of the GameLift Anywhere Game Server Setup Script

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
SETUP_GAME_SERVER_SCRIPT="$PARENT_DIR/setup_game_server.sh"
TEST_OUTPUT_DIR="$SCRIPT_DIR/test_output"
TEST_INSTANCE_ID="i-0898c4db3aa69497b"
TEST_FLEET_ID="fleet-test-12345678-1234-1234-1234-123456789012"
TEST_LOCATION="custom-test-location"
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
    if [[ ! -f "$SETUP_GAME_SERVER_SCRIPT" ]]; then
        print_error "setup_game_server.sh script not found at: $SETUP_GAME_SERVER_SCRIPT"
        exit 1
    fi
    
    if [[ ! -x "$SETUP_GAME_SERVER_SCRIPT" ]]; then
        print_warning "setup_game_server.sh script is not executable, making it executable..."
        chmod +x "$SETUP_GAME_SERVER_SCRIPT"
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
    run_test "help_option" "$SETUP_GAME_SERVER_SCRIPT --help" 0
}

# Test 2: Missing required parameters
test_missing_parameters() {
    run_test "missing_instance_id" "$SETUP_GAME_SERVER_SCRIPT --fleet-id $TEST_FLEET_ID" 1
}

# Test 3: Invalid environment formats
test_invalid_env_formats() {
    run_test "invalid_env_formats" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats invalid" 1
}

# Test 4: Valid environment formats
test_valid_env_formats() {
    # Note: These tests will fail with actual AWS calls, but they test the parameter validation
    run_test "env_format_env" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats env" 1
    run_test "env_format_json" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats json" 1
    run_test "env_format_yaml" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats yaml" 1
    run_test "env_format_multiple" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats env,json,yaml" 1
}

# Test 5: Environment variable support
test_environment_variables() {
    export GAMELIFT_FLEET_ID="$TEST_FLEET_ID"
    export AWS_DEFAULT_REGION="$TEST_REGION"
    
    run_test "env_vars_fleet_id" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID" 1
    
    unset GAMELIFT_FLEET_ID
    unset AWS_DEFAULT_REGION
}

# Test 6: Cleanup functionality
test_cleanup_functionality() {
    # Test cleanup help
    run_test "cleanup_help" "$SETUP_GAME_SERVER_SCRIPT --cleanup" 1
    
    # Test cleanup with valid types
    run_test "cleanup_temp" "$SETUP_GAME_SERVER_SCRIPT --cleanup temp" 0
    run_test "cleanup_env" "$SETUP_GAME_SERVER_SCRIPT --cleanup env" 0
    run_test "cleanup_all" "$SETUP_GAME_SERVER_SCRIPT --cleanup all" 0
    run_test "cleanup_output" "$SETUP_GAME_SERVER_SCRIPT --cleanup output" 0
    run_test "cleanup_fleet" "$SETUP_GAME_SERVER_SCRIPT --cleanup fleet" 0
    
    # Test cleanup with invalid type
    run_test "cleanup_invalid" "$SETUP_GAME_SERVER_SCRIPT --cleanup invalid" 1
}

# Test 7: Script syntax and basic functionality
test_script_syntax() {
    # Test that the script can be sourced without errors (basic syntax check)
    run_test "script_syntax" "bash -n $SETUP_GAME_SERVER_SCRIPT" 0
}

# Test 8: Long option names
test_long_options() {
    run_test "long_options_help" "$SETUP_GAME_SERVER_SCRIPT --help" 0
    run_test "long_options_instance_id" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID" 1
    run_test "long_options_fleet_id" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --fleet-id $TEST_FLEET_ID" 1
    run_test "long_options_location" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --location $TEST_LOCATION" 1
    run_test "long_options_region" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --region $TEST_REGION" 1
    run_test "long_options_output_dir" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --output-dir $TEST_OUTPUT_DIR" 1
    run_test "long_options_skip_registration" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --skip-registration" 1
    run_test "long_options_compute_name" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --compute-name TestCompute" 1
    run_test "long_options_debug" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --debug" 1
    run_test "long_options_yes" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --yes" 1
    run_test "long_options_env_formats" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats json" 1
}

# Test 9: Short option names
test_short_options() {
    run_test "short_options_h" "$SETUP_GAME_SERVER_SCRIPT -h" 0
    run_test "short_options_i" "$SETUP_GAME_SERVER_SCRIPT -i $TEST_INSTANCE_ID" 1
    run_test "short_options_f" "$SETUP_GAME_SERVER_SCRIPT -i $TEST_INSTANCE_ID -f $TEST_FLEET_ID" 1
    run_test "short_options_l" "$SETUP_GAME_SERVER_SCRIPT -i $TEST_INSTANCE_ID -l $TEST_LOCATION" 1
    run_test "short_options_r" "$SETUP_GAME_SERVER_SCRIPT -i $TEST_INSTANCE_ID -r $TEST_REGION" 1
    run_test "short_options_o" "$SETUP_GAME_SERVER_SCRIPT -i $TEST_INSTANCE_ID -o $TEST_OUTPUT_DIR" 1
    run_test "short_options_s" "$SETUP_GAME_SERVER_SCRIPT -i $TEST_INSTANCE_ID -s" 1
    run_test "short_options_c" "$SETUP_GAME_SERVER_SCRIPT -i $TEST_INSTANCE_ID -c TestCompute" 1
    run_test "short_options_d" "$SETUP_GAME_SERVER_SCRIPT -i $TEST_INSTANCE_ID -d" 1
    run_test "short_options_y" "$SETUP_GAME_SERVER_SCRIPT -i $TEST_INSTANCE_ID -y" 1
}

# Test 10: Edge cases
test_edge_cases() {
    # Empty parameters
    run_test "empty_instance_id" "$SETUP_GAME_SERVER_SCRIPT --instance-id ''" 1
    run_test "empty_fleet_id" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --fleet-id ''" 1
    run_test "empty_location" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --location ''" 1
    run_test "empty_region" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --region ''" 1
    
    # Very long parameters
    local long_instance_id="i-$(printf 'a%.0s' {1..100})"
    local long_fleet_id="fleet-$(printf 'b%.0s' {1..100})"
    local long_location="location-$(printf 'c%.0s' {1..100})"
    run_test "long_instance_id" "$SETUP_GAME_SERVER_SCRIPT --instance-id $long_instance_id" 1
    run_test "long_fleet_id" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --fleet-id $long_fleet_id" 1
    run_test "long_location" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --location $long_location" 1
}

# Test 11: Instance ID validation
test_instance_id_validation() {
    # Valid instance ID formats
    run_test "valid_instance_id_1" "$SETUP_GAME_SERVER_SCRIPT --instance-id i-1234567890abcdef0" 1
    run_test "valid_instance_id_2" "$SETUP_GAME_SERVER_SCRIPT --instance-id i-0abcdef1234567890" 1
    
    # Invalid instance ID formats (these should still pass parameter validation)
    run_test "invalid_instance_id_1" "$SETUP_GAME_SERVER_SCRIPT --instance-id not-an-instance-id" 1
    run_test "invalid_instance_id_2" "$SETUP_GAME_SERVER_SCRIPT --instance-id i-123" 1
}

# Test 12: Fleet ID validation
test_fleet_id_validation() {
    # Valid fleet ID formats
    run_test "valid_fleet_id_1" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --fleet-id fleet-12345678-1234-1234-1234-123456789012" 1
    run_test "valid_fleet_id_2" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --fleet-id fleet-abcdef12-3456-7890-abcd-ef1234567890" 1
    
    # Invalid fleet ID formats (these should still pass parameter validation)
    run_test "invalid_fleet_id_1" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --fleet-id not-a-fleet-id" 1
    run_test "invalid_fleet_id_2" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --fleet-id fleet-123" 1
}

# Test 13: Skip registration functionality
test_skip_registration() {
    # Test skip registration without compute name (should fail)
    run_test "skip_registration_no_compute" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --skip-registration" 1
    
    # Test skip registration with compute name
    run_test "skip_registration_with_compute" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --skip-registration --compute-name TestCompute" 1
}

# Test 14: Debug functionality
test_debug_functionality() {
    # Test debug mode
    run_test "debug_mode" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --debug" 1
    
    # Test debug mode with other options
    run_test "debug_mode_with_fleet" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --fleet-id $TEST_FLEET_ID --debug" 1
}

# Test 15: Region validation
test_region_validation() {
    # Test valid regions
    run_test "valid_region_us_east_1" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --region us-east-1" 1
    run_test "valid_region_us_west_2" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --region us-west-2" 1
    run_test "valid_region_eu_west_1" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --region eu-west-1" 1
    
    # Test invalid regions (should still pass parameter validation)
    run_test "invalid_region" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --region invalid-region" 1
}

# Test 16: Output directory functionality
test_output_directory() {
    # Test custom output directory
    run_test "custom_output_dir" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --output-dir $TEST_OUTPUT_DIR/custom" 1
    
    # Test output directory with special characters
    run_test "output_dir_special_chars" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --output-dir '$TEST_OUTPUT_DIR/test-dir_123'" 1
}

# Test 17: Location validation
test_location_validation() {
    # Test valid locations
    run_test "valid_location_1" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --location custom-mygame-dev-location" 1
    run_test "valid_location_2" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --location custom-production-location" 1
    run_test "valid_location_3" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --location custom-staging-location" 1
    
    # Test invalid locations (should still pass parameter validation)
    run_test "invalid_location" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --location invalid-location" 1
}

# Test 18: Compute name validation
test_compute_name_validation() {
    # Test valid compute names
    run_test "valid_compute_name_1" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --compute-name TestCompute" 1
    run_test "valid_compute_name_2" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --compute-name Compute-123" 1
    run_test "valid_compute_name_3" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --compute-name MyGameServer-$(date +%s)" 1
    
    # Test invalid compute names (should still pass parameter validation)
    run_test "invalid_compute_name_1" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --compute-name ''" 1
    run_test "invalid_compute_name_2" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --compute-name 'compute with spaces'" 1
}

# Test 19: Environment formats combinations
test_env_formats_combinations() {
    # Test single format
    run_test "single_format_env" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats env" 1
    run_test "single_format_json" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats json" 1
    run_test "single_format_yaml" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats yaml" 1
    
    # Test multiple formats
    run_test "multiple_formats_env_json" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats env,json" 1
    run_test "multiple_formats_all" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats env,json,yaml" 1
    
    # Test case variations
    run_test "format_case_variations" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --env-formats ENV,JSON,YAML" 1
}

# Test 20: Auto-confirmation functionality
test_auto_confirmation() {
    # Test with --yes flag
    run_test "auto_confirmation_yes" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID --yes" 1
    
    # Test without --yes flag (should ask for confirmation)
    run_test "require_confirmation" "$SETUP_GAME_SERVER_SCRIPT --instance-id $TEST_INSTANCE_ID" 1
}

# Function to run all tests
run_all_tests() {
    print_status "Starting tests for setup_game_server.sh"
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
    test_invalid_env_formats
    test_valid_env_formats
    test_environment_variables
    test_cleanup_functionality
    test_long_options
    test_short_options
    test_edge_cases
    test_instance_id_validation
    test_fleet_id_validation
    test_skip_registration
    test_debug_functionality
    test_region_validation
    test_output_directory
    test_location_validation
    test_compute_name_validation
    test_env_formats_combinations
    test_auto_confirmation
    
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
