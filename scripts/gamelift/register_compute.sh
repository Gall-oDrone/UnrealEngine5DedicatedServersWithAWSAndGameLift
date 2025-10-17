#!/bin/bash

# GameLift Anywhere Compute Registration Script
# This script registers a new compute name for GameLift Anywhere fleets

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
    
    # Check if fleet is an Anywhere fleet
    local compute_type
    compute_type=$(aws gamelift describe-fleet-attributes --fleet-ids "$fleet_id" --query 'FleetAttributes[0].ComputeType' --output text 2>/dev/null)
    
    if [[ "$compute_type" != "ANYWHERE" ]]; then
        print_error "Fleet '$fleet_id' is not an Anywhere fleet (ComputeType: $compute_type)"
        print_status "This script only works with GameLift Anywhere fleets"
        exit 1
    fi
    
    print_success "Fleet ID is valid (Anywhere fleet)"
}

# Function to check if compute name already exists
check_compute_exists() {
    local fleet_id="$1"
    local compute_name="$2"
    
    print_status "Checking if compute name '$compute_name' already exists in fleet '$fleet_id'"
    
    # List all computes for the fleet
    local computes
    if computes=$(aws gamelift list-compute --fleet-id "$fleet_id" --query 'ComputeList[?ComputeName==`'"$compute_name"'`]' --output json 2>/dev/null); then
        local compute_count
        compute_count=$(echo "$computes" | jq '. | length')
        
        if [[ "$compute_count" -gt 0 ]]; then
            print_warning "Compute name '$compute_name' already exists in fleet '$fleet_id'"
            
            # Get compute status
            local compute_status
            compute_status=$(echo "$computes" | jq -r '.[0].Status')
            print_status "Existing compute status: $compute_status"
            
            # Ask user what to do
            echo -n "Do you want to continue anyway? (y/N): "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                print_status "Registration cancelled by user"
                exit 0
            fi
        else
            print_success "Compute name is available"
        fi
    else
        print_warning "Could not check existing computes (fleet may be new or have no computes yet)"
    fi
}

# Function to register compute
register_compute() {
    local fleet_id="$1"
    local compute_name="$2"
    local location="$3"
    local ip_address="$4"
    local region="$5"
    
    print_status "Registering compute '$compute_name' in fleet '$fleet_id'"
    print_status "Location: $location"
    print_status "IP Address: $ip_address"
    
    # Register the compute
    local response
    if ! response=$(aws gamelift register-compute \
        --fleet-id "$fleet_id" \
        --compute-name "$compute_name" \
        --location "$location" \
        --ip-address "$ip_address" \
        --region "$region" \
        --output json 2>&1); then
        print_error "Failed to register compute: $response"
        exit 1
    fi
    
    # Parse the response
    local compute_name_result
    compute_name_result=$(echo "$response" | jq -r '.ComputeName')
    local compute_status
    compute_status=$(echo "$response" | jq -r '.Status')
    
    if [[ "$compute_name_result" == "null" || -z "$compute_name_result" ]]; then
        print_error "No compute name returned in response"
        print_error "Response: $response"
        exit 1
    fi
    
    print_success "Compute registered successfully"
    print_status "Compute Name: $compute_name_result"
    print_status "Status: $compute_status"
    
    echo "$response"
}

# Function to get public IP address
get_public_ip() {
    local ip_address="$1"
    
    if [[ -n "$ip_address" ]]; then
        echo "$ip_address"
        return
    fi
    
    print_status "Detecting public IP address..."
    
    # Try multiple methods to get public IP
    local public_ip=""
    
    # Method 1: AWS metadata service (if running on EC2)
    if public_ip=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null); then
        if [[ -n "$public_ip" && "$public_ip" != "null" ]]; then
            print_success "Found public IP via AWS metadata: $public_ip"
            echo "$public_ip"
            return
        fi
    fi
    
    # Method 2: External services
    for service in "http://checkip.amazonaws.com" "http://ifconfig.me" "http://icanhazip.com"; do
        if public_ip=$(curl -s --connect-timeout 5 "$service" 2>/dev/null | tr -d '\n\r'); then
            if [[ -n "$public_ip" && "$public_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                print_success "Found public IP via $service: $public_ip"
                echo "$public_ip"
                return
            fi
        fi
    done
    
    print_error "Could not automatically detect public IP address"
    print_status "Please provide the public IP address manually using --ip-address option"
    exit 1
}

# Function to generate unique compute name
generate_compute_name() {
    local base_name="$1"
    local timestamp
    timestamp=$(date +%Y-%m-%d-%H-%M-%S)
    
    # Generate a random suffix for uniqueness
    local random_suffix
    random_suffix=$(openssl rand -hex 4 2>/dev/null || echo $(shuf -i 1000-9999 -n 1))
    
    if [[ -n "$base_name" ]]; then
        echo "${base_name}-${timestamp}-${random_suffix}"
    else
        echo "Compute-${timestamp}-${random_suffix}"
    fi
}

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --fleet-id ID        GameLift Anywhere fleet ID (required)"
    echo "  -c, --compute-name NAME  Compute name (optional, auto-generated if not provided)"
    echo "  -l, --location NAME      Location name (default: custom-mygame-dev-location)"
    echo "  -i, --ip-address IP      Public IP address (auto-detected if not provided)"
    echo "  -r, --region REGION      AWS region (default: us-east-1)"
    echo "  -o, --output FORMAT      Output format: text, json (default: text)"
    echo "  -s, --save FILE          Save compute info to file"
    echo "  -y, --yes                Skip confirmation prompts"
    echo "  --cleanup TYPE           Cleanup files and environment (temp, file, env, all, output)"
    echo "  --cleanup-file FILE      Specify file/directory path for cleanup"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --fleet-id fleet-12345678-1234-1234-1234-123456789012"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -c MyGameServer"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -l custom-production-location -i 1.2.3.4"
    echo "  $0 -f fleet-12345678-1234-1234-1234-123456789012 -o json -s compute_info.json"
    echo "  $0 --cleanup temp"
    echo "  $0 --cleanup file --cleanup-file compute_info.json"
    echo "  $0 --cleanup all"
    echo ""
    echo "Environment Variables:"
    echo "  GAMELIFT_FLEET_ID        Default fleet ID"
    echo "  GAMELIFT_COMPUTE_NAME    Default compute name"
    echo "  GAMELIFT_LOCATION        Default location name"
    echo "  AWS_DEFAULT_REGION       Default AWS region"
}

# Function to save compute info to file
save_compute_info() {
    local compute_info="$1"
    local file_path="$2"
    
    print_status "Saving compute info to file: $file_path"
    
    # Create directory if it doesn't exist
    local dir_path=$(dirname "$file_path")
    if [[ ! -d "$dir_path" ]]; then
        mkdir -p "$dir_path"
    fi
    
    # Save compute info
    echo "$compute_info" > "$file_path"
    chmod 644 "$file_path"
    
    print_success "Compute info saved to $file_path"
}

# Function to cleanup temporary files, environment variables, and output files
cleanup_compute_files() {
    local cleanup_type="$1"
    local file_path="$2"
    
    print_status "Starting cleanup process..."
    
    case $cleanup_type in
        "temp")
            # Clean up temporary files in /tmp
            local temp_files=($(find /tmp -name "*gamelift*" -type f 2>/dev/null || true))
            if [[ ${#temp_files[@]} -gt 0 ]]; then
                for file in "${temp_files[@]}"; do
                    rm -f "$file"
                    print_success "Removed temporary file: $file"
                done
            else
                print_warning "No temporary GameLift files found in /tmp"
            fi
            ;;
        "file")
            # Remove specific file
            if [[ -n "$file_path" ]]; then
                if [[ -f "$file_path" ]]; then
                    rm -f "$file_path"
                    print_success "Removed compute info file: $file_path"
                else
                    print_warning "Compute info file not found: $file_path"
                fi
            else
                print_error "File path required for file cleanup"
                return 1
            fi
            ;;
        "env")
            # Clear GameLift-related environment variables
            local env_vars=(
                "GAMELIFT_SDK_WEBSOCKET_URL"
                "GAMELIFT_SDK_FLEET_ID"
                "GAMELIFT_SDK_PROCESS_ID"
                "GAMELIFT_SDK_HOST_ID"
                "GAMELIFT_SDK_AUTH_TOKEN"
                "GAMELIFT_COMPUTE_TYPE"
                "GAMELIFT_REGION"
            )
            
            local cleared_count=0
            for var in "${env_vars[@]}"; do
                if [[ -n "${!var}" ]]; then
                    unset "$var"
                    print_success "Cleared environment variable: $var"
                    ((cleared_count++))
                fi
            done
            
            if [[ $cleared_count -eq 0 ]]; then
                print_warning "No GameLift environment variables were set"
            fi
            ;;
        "all")
            # Clean up everything
            print_status "Performing comprehensive cleanup..."
            
            # Clear environment variables
            cleanup_compute_files "env"
            
            # Remove common output file locations
            local common_paths=(
                "./compute_info.json"
                "./gamelift_compute.json"
                "/tmp/compute_info.json"
                "/tmp/gamelift_compute.json"
                "$HOME/.gamelift_compute_info"
            )
            
            local removed_count=0
            for path in "${common_paths[@]}"; do
                if [[ -f "$path" ]]; then
                    rm -f "$path"
                    print_success "Removed compute info file: $path"
                    ((removed_count++))
                fi
            done
            
            # Clean up temporary files
            cleanup_compute_files "temp"
            
            if [[ $removed_count -eq 0 ]]; then
                print_warning "No common compute info files found to remove"
            fi
            ;;
        "output")
            # Clean up output directory contents
            if [[ -n "$file_path" ]]; then
                if [[ -d "$file_path" ]]; then
                    # Remove only GameLift-related files
                    find "$file_path" -name "*gamelift*" -type f -exec rm -f {} \; 2>/dev/null || true
                    find "$file_path" -name "*compute*" -type f -exec rm -f {} \; 2>/dev/null || true
                    print_success "Cleaned up GameLift files in directory: $file_path"
                else
                    print_warning "Output directory not found: $file_path"
                fi
            else
                print_error "Directory path required for output cleanup"
                return 1
            fi
            ;;
        *)
            print_error "Invalid cleanup type: $cleanup_type"
            print_status "Valid cleanup types: temp, file, env, all, output"
            return 1
            ;;
    esac
    
    print_success "Cleanup completed!"
}

# Function to confirm registration
confirm_registration() {
    local fleet_id="$1"
    local compute_name="$2"
    local location="$3"
    local ip_address="$4"
    local region="$5"
    
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    print_status "Registration Details:"
    echo "  Fleet ID: $fleet_id"
    echo "  Compute Name: $compute_name"
    echo "  Location: $location"
    echo "  IP Address: $ip_address"
    echo "  Region: $region"
    echo ""
    
    echo -n "Do you want to proceed with compute registration? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_status "Registration cancelled by user"
        exit 0
    fi
}

# Main script
main() {
    # Default values
    FLEET_ID=""
    COMPUTE_NAME=""
    LOCATION="${GAMELIFT_LOCATION:-custom-mygame-dev-location}"
    IP_ADDRESS=""
    AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    OUTPUT_FORMAT="text"
    SAVE_FILE=""
    SKIP_CONFIRMATION="false"
    CLEANUP_TYPE=""
    CLEANUP_FILE=""
    
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
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -i|--ip-address)
                IP_ADDRESS="$2"
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
            -s|--save)
                SAVE_FILE="$2"
                shift 2
                ;;
            -y|--yes)
                SKIP_CONFIRMATION="true"
                shift
                ;;
            --cleanup)
                CLEANUP_TYPE="$2"
                shift 2
                ;;
            --cleanup-file)
                CLEANUP_FILE="$2"
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
    
    # Handle cleanup mode
    if [[ -n "$CLEANUP_TYPE" ]]; then
        print_status "GameLift Compute Registration Cleanup"
        cleanup_compute_files "$CLEANUP_TYPE" "$CLEANUP_FILE"
        exit 0
    fi
    
    # Validate required parameters
    if [[ -z "$FLEET_ID" ]]; then
        print_error "Fleet ID is required. Use -f or --fleet-id option."
        show_usage
        exit 1
    fi
    
    # Generate compute name if not provided
    if [[ -z "$COMPUTE_NAME" ]]; then
        COMPUTE_NAME=$(generate_compute_name "DevCompute")
        print_status "Auto-generated compute name: $COMPUTE_NAME"
    fi
    
    # Get public IP address
    IP_ADDRESS=$(get_public_ip "$IP_ADDRESS")
    
    # Validate output format
    if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "json" ]]; then
        print_error "Invalid output format: $OUTPUT_FORMAT. Must be one of: text, json"
        exit 1
    fi
    
    # Set AWS region
    export AWS_DEFAULT_REGION="$AWS_REGION"
    
    print_status "GameLift Anywhere Compute Registration"
    print_status "Fleet ID: $FLEET_ID"
    print_status "Compute Name: $COMPUTE_NAME"
    print_status "Location: $LOCATION"
    print_status "IP Address: $IP_ADDRESS"
    print_status "AWS Region: $AWS_REGION"
    print_status "Output Format: $OUTPUT_FORMAT"
    
    # Check prerequisites
    check_aws_cli
    check_aws_credentials
    check_jq
    
    # Validate fleet ID
    validate_fleet_id "$FLEET_ID"
    
    # Check if compute already exists
    check_compute_exists "$FLEET_ID" "$COMPUTE_NAME"
    
    # Confirm registration
    confirm_registration "$FLEET_ID" "$COMPUTE_NAME" "$LOCATION" "$IP_ADDRESS" "$AWS_REGION"
    
    # Register compute
    COMPUTE_INFO=$(register_compute "$FLEET_ID" "$COMPUTE_NAME" "$LOCATION" "$IP_ADDRESS" "$AWS_REGION")
    
    # Handle output format
    case $OUTPUT_FORMAT in
        "text")
            echo ""
            print_success "Compute Registration Summary:"
            echo "  Compute Name: $(echo "$COMPUTE_INFO" | jq -r '.ComputeName')"
            echo "  Status: $(echo "$COMPUTE_INFO" | jq -r '.Status')"
            echo "  Fleet ID: $FLEET_ID"
            echo "  Location: $LOCATION"
            echo "  IP Address: $IP_ADDRESS"
            echo ""
            print_status "Next steps:"
            echo "  1. Start your game server on this compute"
            echo "  2. The compute will appear in your GameLift console"
            echo "  3. Use the compute name for authentication token generation"
            ;;
        "json")
            echo "$COMPUTE_INFO"
            ;;
    esac
    
    # Save to file if requested
    if [[ -n "$SAVE_FILE" ]]; then
        save_compute_info "$COMPUTE_INFO" "$SAVE_FILE"
    fi
    
    print_success "Compute registration completed!"
    print_warning "Note: The compute may take a few minutes to appear in the GameLift console."
}

# Run main function
main "$@"
