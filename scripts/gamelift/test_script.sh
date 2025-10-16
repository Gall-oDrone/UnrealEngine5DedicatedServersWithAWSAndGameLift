#!/bin/bash

# Test script for GameLift SDK Authentication Token Generator
# This script performs basic validation tests

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATE_SCRIPT="$SCRIPT_DIR/generate_auth_token.sh"

print_info "Testing GameLift SDK Authentication Token Generator"
echo ""

# Test 1: Check if script exists and is executable
print_info "Test 1: Checking script existence and permissions"
if [[ -f "$GENERATE_SCRIPT" ]]; then
    print_success "Script exists: $GENERATE_SCRIPT"
else
    print_error "Script not found: $GENERATE_SCRIPT"
    exit 1
fi

if [[ -x "$GENERATE_SCRIPT" ]]; then
    print_success "Script is executable"
else
    print_error "Script is not executable"
    exit 1
fi

# Test 2: Check script syntax
print_info "Test 2: Checking script syntax"
if bash -n "$GENERATE_SCRIPT"; then
    print_success "Script syntax is valid"
else
    print_error "Script has syntax errors"
    exit 1
fi

# Test 3: Check help functionality
print_info "Test 3: Checking help functionality"
if "$GENERATE_SCRIPT" --help > /dev/null 2>&1; then
    print_success "Help functionality works"
else
    print_error "Help functionality failed"
    exit 1
fi

# Test 4: Check error handling for missing parameters
print_info "Test 4: Checking error handling for missing parameters"
if "$GENERATE_SCRIPT" 2>&1 | grep -q "Fleet ID is required"; then
    print_success "Error handling for missing fleet ID works"
else
    print_error "Error handling for missing fleet ID failed"
    exit 1
fi

# Test 5: Check error handling for invalid output format
print_info "Test 5: Checking error handling for invalid output format"
if "$GENERATE_SCRIPT" --fleet-id test --compute-name test --output invalid 2>&1 | grep -q "Invalid output format"; then
    print_success "Error handling for invalid output format works"
else
    print_error "Error handling for invalid output format failed"
    exit 1
fi

# Test 6: Check AWS CLI dependency
print_info "Test 6: Checking AWS CLI dependency"
if command -v aws &> /dev/null; then
    print_success "AWS CLI is available"
else
    print_error "AWS CLI is not available - this will cause the script to fail"
fi

# Test 7: Check jq dependency
print_info "Test 7: Checking jq dependency"
if command -v jq &> /dev/null; then
    print_success "jq is available"
else
    print_info "jq is not available - script will attempt to install it"
fi

echo ""
print_success "All basic tests passed!"
print_info "Note: To test actual token generation, you need valid AWS credentials and a real fleet ID."
print_info "Run: $GENERATE_SCRIPT --fleet-id YOUR_FLEET_ID --compute-name YOUR_COMPUTE_NAME"
