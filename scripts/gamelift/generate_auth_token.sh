#!/bin/bash

# GameLift SDK Authentication Token Generator
# This script generates a GAMELIFT_SDK_AUTH_TOKEN for authenticating game servers with Amazon GameLift

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        print_status "Installation guide: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        exit 1
    fi
    print_success "AWS CLI is installed"
}

# Function to check if AWS credentials are configured
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    print_success "AWS credentials are configured"
}

# Function to check if jq is installed
check_jq() {
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. Installing jq for JSON parsing..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            if command -v brew &> /dev/null; then
                brew install jq
            else
                print_error "Please install jq manually: https://stedolan.github.io/jq/download/"
                exit 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            # Linux
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y jq
            elif command -v yum &> /dev/null; then
                sudo yum install -y jq
            else
                print_error "Please install jq manually: https://stedolan.github.io/jq/download/"
                exit 1
            fi
        else
            print_error "Please install jq manually: https://stedolan.github.io/jq/download/"
            exit 1
        fi
    fi
    print_success "jq is available"
}

# Function to validate fleet ID
validate_fleet_id() {
    local fleet_id="$1"
    print_status "Validating fleet ID: $fleet_id"
    
    if ! aws gamelift describe-fleet-attributes --fleet-ids "$fleet_id" &> /dev/null; then
        print_error "Fleet ID '$fleet_id' not found or not accessible"
        print_status "Available fleets:"
        aws gamelift list-fleets --query 'FleetIds[]' --output table 2>/dev/null || print_warning "Could not list fleets"
        exit 1
    fi
    print_success "Fleet ID is valid"
}

# Function to generate auth token
generate_auth_token() {
    local fleet_id="$1"
    local compute_name="$2"
    local region="$3"
    
    print_status "Generating authentication token for fleet: $fleet_id, compute: $compute_name" >&2
    
    # Generate the auth token
    local response
    if ! response=$(aws gamelift get-compute-auth-token \
        --fleet-id "$fleet_id" \
        --compute-name "$compute_name" \
        --region "$region" \
        --output json 2>&1); then
        print_error "Failed to generate auth token: $response" >&2
        exit 1
    fi
    
    # Extract the token from the response
    local auth_token
    if ! auth_token=$(echo "$response" | jq -r '.AuthToken'); then
        print_error "Failed to parse auth token from response" >&2
        print_error "Response: $response" >&2
        exit 1
    fi
    
    if [[ "$auth_token" == "null" || -z "$auth_token" ]]; then
        print_error "No auth token found in response" >&2
        print_error "Response: $response" >&2
        exit 1
    fi
    
    print_success "Auth token generated successfully" >&2
    echo "$auth_token"
}

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --fleet-id ID        GameLift fleet ID (required)"
    echo "  -c, --compute-name NAME  Compute name (required)"
    echo "  -r, --region REGION      AWS region (default: us-east-1)"
    echo "  -o, --output FORMAT      Output format: token, env, json (default: token)"
    echo "  -e, --export             Export as environment variable"
    echo "  -s, --save FILE          Save token to file"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --fleet-id fleet-12345678-1234-1234-1234-123456789012 --compute-name MyCompute"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -c MyCompute -o env"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -c MyCompute -e"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -c MyCompute -s /tmp/gamelift_token.txt"
    echo ""
    echo "Environment Variables:"
    echo "  GAMELIFT_FLEET_ID        Default fleet ID"
    echo "  GAMELIFT_COMPUTE_NAME    Default compute name"
    echo "  AWS_DEFAULT_REGION       Default AWS region"
}

# Function to save token to file
save_token_to_file() {
    local token="$1"
    local file_path="$2"
    
    print_status "Saving token to file: $file_path"
    
    # Create directory if it doesn't exist
    local dir_path=$(dirname "$file_path")
    if [[ ! -d "$dir_path" ]]; then
        mkdir -p "$dir_path"
    fi
    
    # Save token with proper permissions
    echo "$token" > "$file_path"
    chmod 600 "$file_path"  # Read/write for owner only
    
    print_success "Token saved to $file_path"
}

# Main script
main() {
    # Default values
    FLEET_ID=""
    COMPUTE_NAME=""
    AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    OUTPUT_FORMAT="token"
    EXPORT_ENV=false
    SAVE_FILE=""
    
    # Check for environment variables
    if [[ -n "$GAMELIFT_FLEET_ID" ]]; then
        FLEET_ID="$GAMELIFT_FLEET_ID"
    fi
    if [[ -n "$GAMELIFT_COMPUTE_NAME" ]]; then
        COMPUTE_NAME="$GAMELIFT_COMPUTE_NAME"
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--fleet-id)
                FLEET_ID="$2"
                shift 2
                ;;
            -c|--compute-name)
                COMPUTE_NAME="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -e|--export)
                EXPORT_ENV=true
                shift
                ;;
            -s|--save)
                SAVE_FILE="$2"
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
    
    if [[ -z "$COMPUTE_NAME" ]]; then
        print_error "Compute name is required. Use -c or --compute-name option."
        show_usage
        exit 1
    fi
    
    # Validate output format
    if [[ "$OUTPUT_FORMAT" != "token" && "$OUTPUT_FORMAT" != "env" && "$OUTPUT_FORMAT" != "json" ]]; then
        print_error "Invalid output format: $OUTPUT_FORMAT. Must be one of: token, env, json"
        exit 1
    fi
    
    # Set AWS region
    export AWS_DEFAULT_REGION="$AWS_REGION"
    
    print_status "GameLift SDK Authentication Token Generator"
    print_status "Fleet ID: $FLEET_ID"
    print_status "Compute Name: $COMPUTE_NAME"
    print_status "AWS Region: $AWS_REGION"
    print_status "Output Format: $OUTPUT_FORMAT"
    
    # Check prerequisites
    check_aws_cli
    check_aws_credentials
    check_jq
    
    # Validate fleet ID
    validate_fleet_id "$FLEET_ID"
    
    # Generate auth token
    AUTH_TOKEN=$(generate_auth_token "$FLEET_ID" "$COMPUTE_NAME" "$AWS_REGION")
    
    # Handle output format
    case $OUTPUT_FORMAT in
        "token")
            echo "$AUTH_TOKEN"
            ;;
        "env")
            echo "export GAMELIFT_SDK_AUTH_TOKEN=\"$AUTH_TOKEN\""
            ;;
        "json")
            echo "{\"AuthToken\": \"$AUTH_TOKEN\", \"FleetId\": \"$FLEET_ID\", \"ComputeName\": \"$COMPUTE_NAME\", \"Region\": \"$AWS_REGION\"}"
            ;;
    esac
    
    # Export environment variable if requested
    if [[ "$EXPORT_ENV" == true ]]; then
        export GAMELIFT_SDK_AUTH_TOKEN="$AUTH_TOKEN"
        print_success "Environment variable GAMELIFT_SDK_AUTH_TOKEN has been set"
    fi
    
    # Save to file if requested
    if [[ -n "$SAVE_FILE" ]]; then
        save_token_to_file "$AUTH_TOKEN" "$SAVE_FILE"
    fi
    
    print_success "Authentication token generation completed!"
    print_warning "Note: Auth tokens are valid for a limited time (typically 3 hours). Refresh as needed."
}

# Run main function
main "$@"
