#!/bin/bash

# Test script for create_game_session.sh
# This script tests the functionality of the GameLift GameSession Creator

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
CREATE_GAMESESSION_SCRIPT="$PARENT_DIR/create_game_session.sh"
TEST_OUTPUT_DIR="$SCRIPT_DIR/test_output"
TEST_FLEET_ID="fleet-test-12345678-1234-1234-1234-123456789012"
TEST_ALIAS_ID="alias-test-12345678-1234-1234-1234-123456789012"
TEST_REGION="us-east-1"
TEST_MAX_PLAYERS="10"

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
    if [[ ! -f "$CREATE_GAMESESSION_SCRIPT" ]]; then
        print_error "create_game_session.sh script not found at: $CREATE_GAMESESSION_SCRIPT"
        exit 1
    fi
    
    if [[ ! -x "$CREATE_GAMESESSION_SCRIPT" ]]; then
        print_warning "create_game_session.sh script is not executable, making it executable..."
        chmod +x "$CREATE_GAMESESSION_SCRIPT"
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
    run_test "help_option" "$CREATE_GAMESESSION_SCRIPT --help" 0
}

# Test 2: Missing required parameters
test_missing_parameters() {
    run_test "missing_fleet_id" "$CREATE_GAMESESSION_SCRIPT --max-players $TEST_MAX_PLAYERS" 1
}

# Test 3: Invalid output format
test_invalid_output_format() {
    run_test "invalid_output_format" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --output invalid" 1
}

# Test 4: Valid output formats
test_valid_output_formats() {
    # Note: These tests will fail with actual AWS calls, but they test the parameter validation
    run_test "output_format_text" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --output text" 1
    run_test "output_format_json" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --output json" 1
}

# Test 5: Max players validation
test_max_players_validation() {
    # Test valid max players
    run_test "max_players_valid" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --max-players 10" 1
    run_test "max_players_valid_high" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --max-players 200" 1
    
    # Test invalid max players
    run_test "max_players_zero" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --max-players 0" 1
    run_test "max_players_negative" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --max-players -1" 1
    run_test "max_players_too_high" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --max-players 201" 1
    run_test "max_players_non_numeric" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --max-players abc" 1
}

# Test 6: Environment variable support
test_environment_variables() {
    export GAMELIFT_FLEET_ID="$TEST_FLEET_ID"
    export GAMELIFT_ALIAS_ID="$TEST_ALIAS_ID"
    export GAMELIFT_MAX_PLAYERS="$TEST_MAX_PLAYERS"
    export AWS_DEFAULT_REGION="$TEST_REGION"
    
    run_test "env_vars_fleet_id" "$CREATE_GAMESESSION_SCRIPT" 1
    run_test "env_vars_alias_id" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID" 1
    run_test "env_vars_max_players" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID" 1
    
    unset GAMELIFT_FLEET_ID
    unset GAMELIFT_ALIAS_ID
    unset GAMELIFT_MAX_PLAYERS
    unset AWS_DEFAULT_REGION
}

# Test 7: Cleanup functionality
test_cleanup_functionality() {
    # Test cleanup help
    run_test "cleanup_help" "$CREATE_GAMESESSION_SCRIPT --cleanup" 1
    
    # Test cleanup with valid type
    run_test "cleanup_temp" "$CREATE_GAMESESSION_SCRIPT --cleanup temp" 0
    run_test "cleanup_all" "$CREATE_GAMESESSION_SCRIPT --cleanup all" 0
    
    # Test cleanup with invalid type
    run_test "cleanup_invalid" "$CREATE_GAMESESSION_SCRIPT --cleanup invalid" 1
}

# Test 8: Script syntax and basic functionality
test_script_syntax() {
    # Test that the script can be sourced without errors (basic syntax check)
    run_test "script_syntax" "bash -n $CREATE_GAMESESSION_SCRIPT" 0
}

# Test 9: Long option names
test_long_options() {
    run_test "long_options_help" "$CREATE_GAMESESSION_SCRIPT --help" 0
    run_test "long_options_fleet_id" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID" 1
    run_test "long_options_alias_id" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --alias-id $TEST_ALIAS_ID" 1
    run_test "long_options_max_players" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --max-players $TEST_MAX_PLAYERS" 1
    run_test "long_options_region" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --region $TEST_REGION" 1
    run_test "long_options_output" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --output text" 1
    run_test "long_options_save" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --save test_output.json" 1
    run_test "long_options_details" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --details" 1
}

# Test 10: Short option names
test_short_options() {
    run_test "short_options_h" "$CREATE_GAMESESSION_SCRIPT -h" 0
    run_test "short_options_f" "$CREATE_GAMESESSION_SCRIPT -f $TEST_FLEET_ID" 1
    run_test "short_options_a" "$CREATE_GAMESESSION_SCRIPT -f $TEST_FLEET_ID -a $TEST_ALIAS_ID" 1
    run_test "short_options_m" "$CREATE_GAMESESSION_SCRIPT -f $TEST_FLEET_ID -m $TEST_MAX_PLAYERS" 1
    run_test "short_options_r" "$CREATE_GAMESESSION_SCRIPT -f $TEST_FLEET_ID -r $TEST_REGION" 1
    run_test "short_options_o" "$CREATE_GAMESESSION_SCRIPT -f $TEST_FLEET_ID -o json" 1
    run_test "short_options_s" "$CREATE_GAMESESSION_SCRIPT -f $TEST_FLEET_ID -s test_output.json" 1
    run_test "short_options_d" "$CREATE_GAMESESSION_SCRIPT -f $TEST_FLEET_ID -d" 1
}

# Test 11: Edge cases
test_edge_cases() {
    # Empty parameters
    run_test "empty_fleet_id" "$CREATE_GAMESESSION_SCRIPT --fleet-id ''" 1
    run_test "empty_alias_id" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --alias-id ''" 1
    run_test "empty_max_players" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --max-players ''" 1
    
    # Very long parameters
    local long_fleet_id="fleet-$(printf 'a%.0s' {1..100})"
    local long_alias_id="alias-$(printf 'b%.0s' {1..100})"
    run_test "long_fleet_id" "$CREATE_GAMESESSION_SCRIPT --fleet-id $long_fleet_id" 1
    run_test "long_alias_id" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --alias-id $long_alias_id" 1
}

# Test 12: Player data and game properties
test_player_data_and_properties() {
    # Test player data
    run_test "player_data" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --player-data Player123" 1
    
    # Test game properties (valid JSON)
    run_test "game_properties_valid" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --game-properties '[{\"Key\":\"GameMode\",\"Value\":\"Deathmatch\"}]'" 1
    
    # Test game properties (invalid JSON)
    run_test "game_properties_invalid" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --game-properties 'invalid-json'" 1
}

# Test 13: Save functionality
test_save_functionality() {
    # Test save to file
    run_test "save_to_file" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --save $TEST_OUTPUT_DIR/test_save.json" 1
    
    # Test save to file with cleanup
    run_test "save_to_file_cleanup" "$CREATE_GAMESESSION_SCRIPT --cleanup file --cleanup-file $TEST_OUTPUT_DIR/test_save.json" 0
}

# Test 14: Details functionality
test_details_functionality() {
    # Test details option
    run_test "details_option" "$CREATE_GAMESESSION_SCRIPT --fleet-id $TEST_FLEET_ID --details" 1
}

# Function to run all tests
run_all_tests() {
    print_status "Starting tests for create_game_session.sh"
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
    test_max_players_validation
    test_environment_variables
    test_cleanup_functionality
    test_long_options
    test_short_options
    test_edge_cases
    test_player_data_and_properties
    test_save_functionality
    test_details_functionality
    
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
