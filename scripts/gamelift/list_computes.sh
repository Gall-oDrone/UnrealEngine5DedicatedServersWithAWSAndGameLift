#!/bin/bash

# GameLift Compute Lister
# This script lists all compute resources for a given fleet

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --fleet-id ID        GameLift fleet ID (required)"
    echo "  -r, --region REGION      AWS region (default: us-east-1)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --fleet-id fleet-12345678-1234-1234-1234-123456789012"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -r us-west-2"
}

# Main script
main() {
    # Default values
    FLEET_ID=""
    AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--fleet-id)
                FLEET_ID="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$FLEET_ID" ]]; then
        print_error "Fleet ID is required. Use -f or --fleet-id option."
        show_usage
        exit 1
    fi
    
    # Set AWS region
    export AWS_DEFAULT_REGION="$AWS_REGION"
    
    print_status "Listing compute resources for fleet: $FLEET_ID"
    print_status "AWS Region: $AWS_REGION"
    
    # List computes
    if ! aws gamelift list-compute --fleet-id "$FLEET_ID" --region "$AWS_REGION" --output table; then
        print_error "Failed to list compute resources for fleet: $FLEET_ID"
        print_status "Make sure the fleet ID is correct and you have the necessary permissions."
        exit 1
    fi
    
    print_success "Compute listing completed!"
}

# Run main function
main "$@"
