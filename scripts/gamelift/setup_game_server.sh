#!/bin/bash

# GameLift Anywhere Game Server Setup Script
# This script orchestrates compute registration and auth token generation for EC2 instances

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

# Function to check if fleet is an Anywhere fleet
check_fleet_type() {
    local fleet_id="$1"
    
    if [[ -z "$fleet_id" ]]; then
        return 1  # No fleet provided
    fi
    
    print_status "Checking fleet type for: $fleet_id"
    
    # Check if fleet exists and get compute type
    local compute_type
    if ! compute_type=$(aws gamelift describe-fleet-attributes --fleet-ids "$fleet_id" --query 'FleetAttributes[0].ComputeType' --output text 2>/dev/null); then
        print_error "Fleet '$fleet_id' not found or not accessible"
        return 1
    fi
    
    if [[ "$compute_type" == "ANYWHERE" ]]; then
        print_success "Fleet is a GameLift Anywhere fleet"
        return 0
    else
        print_warning "Fleet '$fleet_id' is not an Anywhere fleet (ComputeType: $compute_type)"
        return 1
    fi
}

# Function to create a GameLift Anywhere fleet
create_anywhere_fleet() {
    local fleet_name="$1"
    local region="$2"
    
    print_status "Creating GameLift Anywhere fleet: $fleet_name"
    
    # Create the Anywhere fleet
    local fleet_id
    if ! fleet_id=$(aws gamelift create-fleet \
        --name "$fleet_name" \
        --description "GameLift Anywhere fleet for custom compute" \
        --compute-type "ANYWHERE" \
        --locations '[{"Location":"custom-mygame-dev-location"}]' \
        --query 'FleetAttributes.FleetId' \
        --output text 2>/dev/null); then
        print_error "Failed to create GameLift Anywhere fleet"
        return 1
    fi
    
    print_success "Created GameLift Anywhere fleet: $fleet_id"
    print_status "Fleet Name: $fleet_name"
    print_status "Fleet ID: $fleet_id"
    
    # Wait a moment for the fleet to be fully created
    print_status "Waiting for fleet to be ready..."
    sleep 5
    
    echo "$fleet_id"
}

# Function to get instance information
get_instance_info() {
    local instance_id="$1"
    
    print_status "Getting information for instance: $instance_id"
    
    # Check if instance exists
    if ! aws ec2 describe-instances --instance-ids "$instance_id" &> /dev/null; then
        print_error "Instance ID '$instance_id' not found or not accessible"
        exit 1
    fi
    
    # Get instance details
    local instance_info
    instance_info=$(aws ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[0].Instances[0]' --output json)
    
    # Extract information
    local instance_state
    instance_state=$(echo "$instance_info" | jq -r '.State.Name')
    local public_ip
    public_ip=$(echo "$instance_info" | jq -r '.PublicIpAddress // empty')
    local private_ip
    private_ip=$(echo "$instance_info" | jq -r '.PrivateIpAddress')
    local instance_type
    instance_type=$(echo "$instance_info" | jq -r '.InstanceType')
    local availability_zone
    availability_zone=$(echo "$instance_info" | jq -r '.Placement.AvailabilityZone')
    
    # Validate instance state
    if [[ "$instance_state" != "running" ]]; then
        print_error "Instance '$instance_id' is not running (State: $instance_state)"
        print_status "Please ensure the instance is running before proceeding"
        exit 1
    fi
    
    # Check if public IP is available
    if [[ -z "$public_ip" || "$public_ip" == "null" ]]; then
        print_error "Instance '$instance_id' does not have a public IP address"
        print_status "GameLift Anywhere requires instances with public IP addresses"
        exit 1
    fi
    
    print_success "Instance information retrieved successfully"
    print_status "Instance State: $instance_state"
    print_status "Public IP: $public_ip"
    print_status "Private IP: $private_ip"
    print_status "Instance Type: $instance_type"
    print_status "Availability Zone: $availability_zone"
    
    # Export variables for use by other functions
    export INSTANCE_PUBLIC_IP="$public_ip"
    export INSTANCE_PRIVATE_IP="$private_ip"
    export INSTANCE_TYPE="$instance_type"
    export INSTANCE_AZ="$availability_zone"
}

# Function to generate compute name based on instance
generate_compute_name() {
    local instance_id="$1"
    local instance_type="$2"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    
    # Create a meaningful compute name
    local compute_name="Compute-${instance_id}-${instance_type}-${timestamp}"
    
    # Clean up the name (remove invalid characters)
    compute_name=$(echo "$compute_name" | sed 's/i-//g' | sed 's/\./-/g')
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_status "Generated compute name: $compute_name" >&2
    fi
    
    echo "$compute_name"
}

# Function to run register_compute.sh
run_register_compute() {
    local fleet_id="$1"
    local compute_name="$2"
    local location="$3"
    local ip_address="$4"
    local region="$5"
    
    print_status "Registering compute with GameLift..."
    
    # Build the command
    local script_dir="$(dirname "$0")"
    local register_cmd="$script_dir/register_compute.sh"
    register_cmd="$register_cmd --fleet-id $fleet_id"
    register_cmd="$register_cmd --compute-name $compute_name"
    register_cmd="$register_cmd --location $location"
    register_cmd="$register_cmd --ip-address $ip_address"
    register_cmd="$register_cmd --region $region"
    register_cmd="$register_cmd --yes"  # Skip confirmation
    
    print_status "Running: $register_cmd"
    
    # Execute the command
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_status "Debug: Executing register_compute.sh command"
        print_status "Debug: Full command: $register_cmd"
    fi
    
    # Execute the command and capture output
    eval "$register_cmd" > /tmp/register_output.txt 2>&1
    local register_exit_code=$?
    
    # Check if the compute was actually registered by looking for success indicators
    if ! grep -q "Compute registration completed" /tmp/register_output.txt; then
        print_error "Failed to register compute"
        print_error "Command output:"
        cat /tmp/register_output.txt
        exit 1
    fi
    
    # Even if there are JSON parsing errors in the output, if the compute was registered, continue
    if [[ $register_exit_code -ne 0 ]]; then
        print_warning "Register compute script had some issues but compute was registered successfully"
        if [[ "$DEBUG_MODE" == "true" ]]; then
            print_status "Register compute output (with warnings):"
            cat /tmp/register_output.txt
        fi
    fi
    
    print_success "Compute registered successfully"
    
    # Extract compute name from output (in case it was modified)
    local registered_compute_name
    registered_compute_name=$(grep "Compute Name:" /tmp/register_output.txt | head -1 | sed 's/.*Compute Name: //')
    
    if [[ -z "$registered_compute_name" ]]; then
        registered_compute_name="$compute_name"
    fi
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_status "Register compute output:"
        cat /tmp/register_output.txt
    fi
    
    echo "$registered_compute_name"
}

# Function to run generate_auth_token.sh
run_generate_auth_token() {
    local fleet_id="$1"
    local compute_name="$2"
    local region="$3"
    
    print_status "Generating authentication token..."
    
    # Build the command
    local script_dir="$(dirname "$0")"
    local auth_cmd="$script_dir/generate_auth_token.sh"
    auth_cmd="$auth_cmd --fleet-id $fleet_id"
    auth_cmd="$auth_cmd --compute-name $compute_name"
    auth_cmd="$auth_cmd --region $region"
    auth_cmd="$auth_cmd --output env"
    
    print_status "Running: $auth_cmd"
    
    # Execute the command
    if ! eval "$auth_cmd" > /tmp/auth_output.txt 2>&1; then
        print_error "Failed to generate auth token"
        print_error "Command output:"
        cat /tmp/auth_output.txt
        exit 1
    fi
    
    print_success "Auth token generated successfully"
    
    # Extract the auth token
    local auth_token
    auth_token=$(grep "GAMELIFT_SDK_AUTH_TOKEN=" /tmp/auth_output.txt | sed 's/export GAMELIFT_SDK_AUTH_TOKEN="//' | sed 's/"$//')
    
    if [[ -z "$auth_token" ]]; then
        print_error "Could not extract auth token from output"
        print_error "Auth token generation output:"
        cat /tmp/auth_output.txt
        exit 1
    fi
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_status "Auth token generation output:"
        cat /tmp/auth_output.txt
    fi
    
    echo "$auth_token"
}

# Function to create server startup script
create_startup_script() {
    local fleet_id="$1"
    local compute_name="$2"
    local auth_token="$3"
    local ip_address="$4"
    local region="$5"
    local output_file="$6"
    
    print_status "Creating server startup script..."
    
    cat > "$output_file" << EOF
#!/bin/bash

# GameLift Anywhere Server Startup Script
# Generated on $(date)

# GameLift Configuration
export GAMELIFT_SDK_WEBSOCKET_URL="wss://${region}.api.amazongamelift.com"
export GAMELIFT_SDK_FLEET_ID="${fleet_id}"
export GAMELIFT_SDK_PROCESS_ID="${compute_name}-$(date +%s)"
export GAMELIFT_SDK_HOST_ID="${compute_name}"
export GAMELIFT_SDK_AUTH_TOKEN="${auth_token}"
export GAMELIFT_COMPUTE_TYPE="ANYWHERE"
export GAMELIFT_REGION="${region}"

# Server Configuration
SERVER_PORT=7777
MAX_PLAYERS=10
LOG_LEVEL=verbose

echo "Starting GameLift Anywhere Server..."
echo "Fleet ID: ${fleet_id}"
echo "Compute Name: ${compute_name}"
echo "Server Port: ${SERVER_PORT}"
echo "Max Players: ${MAX_PLAYERS}"
echo "IP Address: ${ip_address}"

# Start the server
./FPSTemplateServer \\
    -port \${SERVER_PORT} \\
    -maxplayers \${MAX_PLAYERS} \\
    -log \\
    -logFile /local/game/logs/server.log \\
    -glAnywhere=true \\
    -glAnywhereWebSocketUrl=\${GAMELIFT_SDK_WEBSOCKET_URL} \\
    -glAnywhereFleetId=\${GAMELIFT_SDK_FLEET_ID} \\
    -glAnywhereProcessId=\${GAMELIFT_SDK_PROCESS_ID} \\
    -glAnywhereHostId=\${GAMELIFT_SDK_HOST_ID} \\
    -glAnywhereAuthToken=\${GAMELIFT_SDK_AUTH_TOKEN} \\
    -glAnywhereAwsRegion=\${GAMELIFT_REGION}

EOF
    
    chmod +x "$output_file"
    print_success "Startup script created: $output_file"
}

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -i, --instance-id ID      EC2 instance ID (required)"
    echo "  -f, --fleet-id ID         GameLift Anywhere fleet ID (optional - will create one if not provided)"
    echo "  -l, --location NAME       Location name (default: custom-mygame-dev-location)"
    echo "  -r, --region REGION       AWS region (default: us-east-1)"
    echo "  -o, --output-dir DIR      Output directory for generated files (default: ./output)"
    echo "  -s, --skip-registration   Skip compute registration (use existing compute)"
    echo "  -c, --compute-name NAME   Existing compute name (required with --skip-registration)"
    echo "  -d, --debug               Enable debug output"
    echo "  -y, --yes                 Skip confirmation prompts (auto-create fleets)"
    echo "  --cleanup TYPE            Cleanup files and environment (temp, file, env, all, output, fleet, delete-fleet, delete-all-fleets, delete-fleet-force, delete-all-fleets-force)"
    echo "  --cleanup-file FILE       Specify file/directory path for cleanup"
    echo "  --env-formats FORMATS     Generate environment files in specified formats (env,json,yaml) - comma-separated"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --instance-id i-1234567890abcdef0"
    echo "  $0 -i i-1234567890abcdef0 -f fleet-12345678-1234-1234-1234-123456789012"
    echo "  $0 -i i-1234567890abcdef0 -l custom-production-location"
    echo "  $0 -i i-1234567890abcdef0 -o /tmp/gamelift-setup"
    echo "  $0 -i i-1234567890abcdef0 --skip-registration -c MyExistingCompute"
    echo "  $0 --cleanup temp"
    echo "  $0 --cleanup file --cleanup-file ./output/start_game_server.sh"
    echo "  $0 --cleanup all"
    echo "  $0 --cleanup output"
    echo "  $0 --cleanup delete-fleet --cleanup-file fleet-12345678-1234-1234-1234-123456789012"
    echo "  $0 --cleanup delete-all-fleets"
    echo "  $0 --cleanup delete-fleet-force --cleanup-file fleet-12345678-1234-1234-1234-123456789012"
    echo "  $0 -i i-1234567890abcdef0 --env-formats env,json,yaml"
    echo ""
    echo "Environment Variables:"
    echo "  GAMELIFT_FLEET_ID        Default fleet ID"
    echo "  AWS_DEFAULT_REGION       Default AWS region"
}

# Function to generate environment variable files
generate_env_files() {
    local fleet_id="$1"
    local compute_name="$2"
    local auth_token="$3"
    local region="$4"
    local output_dir="$5"
    local formats="$6"  # Comma-separated list: env,json,yaml
    
    print_status "Generating environment variable files..."
    
    # Set default formats if not provided
    if [[ -z "$formats" ]]; then
        formats="env,json"
    fi
    
    # Convert comma-separated to array
    IFS=',' read -ra format_array <<< "$formats"
    
    for format in "${format_array[@]}"; do
        case $format in
            "env")
                generate_env_file "$fleet_id" "$compute_name" "$auth_token" "$region" "$output_dir"
                ;;
            "json")
                generate_json_file "$fleet_id" "$compute_name" "$auth_token" "$region" "$output_dir"
                ;;
            "yaml"|"yml")
                generate_yaml_file "$fleet_id" "$compute_name" "$auth_token" "$region" "$output_dir"
                ;;
            *)
                print_warning "Unknown format: $format (skipping)"
                ;;
        esac
    done
}

# Function to generate .env file
generate_env_file() {
    local fleet_id="$1"
    local compute_name="$2"
    local auth_token="$3"
    local region="$4"
    local output_dir="$5"
    
    local env_file="$output_dir/gamelift.env"
    
    print_status "Generating .env file: $env_file"
    
    cat > "$env_file" << EOF
# GameLift Anywhere Environment Variables
# Generated on $(date)

# GameLift SDK Configuration
export GAMELIFT_SDK_AUTH_TOKEN="${auth_token}"
export GAMELIFT_SDK_FLEET_ID="${fleet_id}"
export GAMELIFT_SDK_HOST_ID="${compute_name}"
export GAMELIFT_SDK_WEBSOCKET_URL="wss://${region}.api.amazongamelift.com"
export GAMELIFT_SDK_PROCESS_ID="${compute_name}-\$(date +%s)"
export GAMELIFT_COMPUTE_TYPE="ANYWHERE"
export GAMELIFT_REGION="${region}"

# Additional GameLift Variables
export GAMELIFT_FLEET_ID="${fleet_id}"
export GAMELIFT_COMPUTE_NAME="${compute_name}"
export GAMELIFT_LOCATION="custom-mygame-dev-location"
EOF
    
    chmod 644 "$env_file"
    print_success "Generated .env file: $env_file"
}

# Function to generate JSON file
generate_json_file() {
    local fleet_id="$1"
    local compute_name="$2"
    local auth_token="$3"
    local region="$4"
    local output_dir="$5"
    
    local json_file="$output_dir/gamelift_config.json"
    
    print_status "Generating JSON file: $json_file"
    
    cat > "$json_file" << EOF
{
  "gamelift": {
    "sdk": {
      "auth_token": "${auth_token}",
      "fleet_id": "${fleet_id}",
      "host_id": "${compute_name}",
      "websocket_url": "wss://${region}.api.amazongamelift.com",
      "process_id": "${compute_name}-$(date +%s)",
      "compute_type": "ANYWHERE",
      "region": "${region}"
    },
    "fleet_id": "${fleet_id}",
    "compute_name": "${compute_name}",
    "location": "custom-mygame-dev-location",
    "generated_at": "$(date -Iseconds)"
  }
}
EOF
    
    chmod 644 "$json_file"
    print_success "Generated JSON file: $json_file"
}

# Function to generate YAML file
generate_yaml_file() {
    local fleet_id="$1"
    local compute_name="$2"
    local auth_token="$3"
    local region="$4"
    local output_dir="$5"
    
    local yaml_file="$output_dir/gamelift_config.yaml"
    
    print_status "Generating YAML file: $yaml_file"
    
    cat > "$yaml_file" << EOF
# GameLift Anywhere Configuration
# Generated on $(date)

gamelift:
  sdk:
    auth_token: "${auth_token}"
    fleet_id: "${fleet_id}"
    host_id: "${compute_name}"
    websocket_url: "wss://${region}.api.amazongamelift.com"
    process_id: "${compute_name}-$(date +%s)"
    compute_type: "ANYWHERE"
    region: "${region}"
  fleet_id: "${fleet_id}"
  compute_name: "${compute_name}"
  location: "custom-mygame-dev-location"
  generated_at: "$(date -Iseconds)"
EOF
    
    chmod 644 "$yaml_file"
    print_success "Generated YAML file: $yaml_file"
}

# Function to delete GameLift fleet
delete_gamelift_fleet() {
    local fleet_id="$1"
    local force_delete="$2"
    
    if [[ -z "$fleet_id" ]]; then
        print_error "Fleet ID is required for fleet deletion"
        return 1
    fi
    
    print_status "Deleting GameLift fleet: $fleet_id"
    
    # Check if fleet exists
    if ! aws gamelift describe-fleet-attributes --fleet-ids "$fleet_id" &> /dev/null; then
        print_error "Fleet '$fleet_id' not found or not accessible"
        return 1
    fi
    
    # Get fleet status
    local fleet_status
    fleet_status=$(aws gamelift describe-fleet-attributes --fleet-ids "$fleet_id" --query 'FleetAttributes[0].Status' --output text 2>/dev/null)
    
    if [[ "$fleet_status" == "DELETING" ]]; then
        print_warning "Fleet '$fleet_id' is already being deleted"
        return 0
    fi
    
    # Check if fleet has active computes
    local compute_count
    compute_count=$(aws gamelift list-compute --fleet-id "$fleet_id" --query 'ComputeList | length(@)' --output text 2>/dev/null || echo "0")
    
    if [[ "$compute_count" -gt 0 && "$force_delete" != "true" ]]; then
        print_warning "Fleet '$fleet_id' has $compute_count active compute(s)"
        print_status "Use --force flag to delete fleet with active computes"
        return 1
    fi
    
    # Delete the fleet
    if aws gamelift delete-fleet --fleet-id "$fleet_id" &> /dev/null; then
        print_success "Fleet deletion initiated: $fleet_id"
        print_status "Note: Fleet deletion may take several minutes to complete"
    else
        print_error "Failed to delete fleet: $fleet_id"
        return 1
    fi
}

# Function to list and delete all GameLift fleets
delete_all_fleets() {
    local force_delete="$1"
    
    print_status "Listing all GameLift fleets..."
    
    # Get all fleet IDs
    local fleet_ids
    fleet_ids=$(aws gamelift list-fleets --query 'FleetIds[]' --output text 2>/dev/null)
    
    if [[ -z "$fleet_ids" ]]; then
        print_warning "No GameLift fleets found"
        return 0
    fi
    
    print_status "Found fleets: $fleet_ids"
    
    if [[ "$force_delete" != "true" ]]; then
        echo -n "Are you sure you want to delete ALL GameLift fleets? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_status "Fleet deletion cancelled by user"
            return 0
        fi
    fi
    
    local deleted_count=0
    local failed_count=0
    
    for fleet_id in $fleet_ids; do
        if delete_gamelift_fleet "$fleet_id" "$force_delete"; then
            ((deleted_count++))
        else
            ((failed_count++))
        fi
    done
    
    print_status "Fleet deletion summary:"
    print_status "  Successfully deleted: $deleted_count"
    print_status "  Failed to delete: $failed_count"
}

# Function to cleanup only temporary files created during this script run
cleanup_temp_files() {
    # Only clean up the specific temporary files we create during this run
    local temp_files=(
        "/tmp/register_output.txt"
        "/tmp/auth_output.txt"
    )
    
    local removed_count=0
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            ((removed_count++))
        fi
    done
    
    # Only print cleanup message if we actually removed files
    if [[ $removed_count -gt 0 ]]; then
        print_status "Cleaned up $removed_count temporary file(s) from this run"
    fi
}

# Function to cleanup temporary files, environment variables, and output files
cleanup() {
    local cleanup_type="${1:-auto}"
    local file_path="$2"
    
    print_status "Starting cleanup process..."
    
    case $cleanup_type in
        "auto"|"temp")
            # Clean up temporary files created during script execution
            local temp_files=(
                "/tmp/register_output.txt"
                "/tmp/auth_output.txt"
            )
            
            # Also find any other temporary GameLift files
            local temp_gamelift_files=($(find /tmp -name "*gamelift*" -type f 2>/dev/null || true))
            temp_files+=("${temp_gamelift_files[@]}")
            
            local removed_count=0
            for file in "${temp_files[@]}"; do
                if [[ -f "$file" ]]; then
                    rm -f "$file"
                    print_success "Removed temporary file: $file"
                    ((removed_count++))
                fi
            done
            
            if [[ $removed_count -eq 0 ]]; then
                print_warning "No temporary files found to remove"
            fi
            ;;
        "file")
            # Remove specific file
            if [[ -n "$file_path" ]]; then
                if [[ -f "$file_path" ]]; then
                    rm -f "$file_path"
                    print_success "Removed file: $file_path"
                else
                    print_warning "File not found: $file_path"
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
                "GAMELIFT_FLEET_ID"
                "GAMELIFT_COMPUTE_NAME"
                "GAMELIFT_LOCATION"
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
            cleanup "env"
            
            # Remove common output file locations
            local common_paths=(
                "./output"
                "./gamelift_setup"
                "/tmp/gamelift_setup"
                "/tmp/gamelift_output"
                "$HOME/.gamelift_setup"
                "./start_game_server.sh"
                "./gamelift_config.txt"
                "./compute_info.json"
                "./gamelift_compute.json"
            )
            
            local removed_count=0
            for path in "${common_paths[@]}"; do
                if [[ -f "$path" ]]; then
                    rm -f "$path"
                    print_success "Removed file: $path"
                    ((removed_count++))
                elif [[ -d "$path" ]]; then
                    rm -rf "$path"
                    print_success "Removed directory: $path"
                    ((removed_count++))
                fi
            done
            
            # Clean up temporary files
            cleanup "temp"
            
            if [[ $removed_count -eq 0 ]]; then
                print_warning "No common files or directories found to remove"
            fi
            ;;
        "output")
            # Clean up output directory contents
            if [[ -n "$file_path" ]]; then
                if [[ -d "$file_path" ]]; then
                    # Remove only GameLift-related files
                    find "$file_path" -name "*gamelift*" -type f -exec rm -f {} \; 2>/dev/null || true
                    find "$file_path" -name "*compute*" -type f -exec rm -f {} \; 2>/dev/null || true
                    find "$file_path" -name "start_game_server.sh" -type f -exec rm -f {} \; 2>/dev/null || true
                    find "$file_path" -name "gamelift_config.txt" -type f -exec rm -f {} \; 2>/dev/null || true
                    print_success "Cleaned up GameLift files in directory: $file_path"
                else
                    print_warning "Output directory not found: $file_path"
                fi
            else
                # Use default output directory
                local default_output="./output"
                if [[ -d "$default_output" ]]; then
                    cleanup "output" "$default_output"
                else
                    print_warning "Default output directory not found: $default_output"
                fi
            fi
            ;;
        "fleet")
            # Clean up fleet-related files and environment (but not delete the actual fleet)
            print_status "Cleaning up fleet-related resources..."
            
            # Clear fleet environment variables
            local fleet_env_vars=(
                "GAMELIFT_FLEET_ID"
                "GAMELIFT_SDK_FLEET_ID"
            )
            
            for var in "${fleet_env_vars[@]}"; do
                if [[ -n "${!var}" ]]; then
                    unset "$var"
                    print_success "Cleared fleet environment variable: $var"
                fi
            done
            
            # Remove fleet-related files
            local fleet_files=(
                "./fleet_info.json"
                "./gamelift_fleet.json"
                "/tmp/fleet_info.json"
                "/tmp/gamelift_fleet.json"
            )
            
            for file in "${fleet_files[@]}"; do
                if [[ -f "$file" ]]; then
                    rm -f "$file"
                    print_success "Removed fleet file: $file"
                fi
            done
            ;;
        "delete-fleet")
            # Delete the actual GameLift fleet
            if [[ -n "$file_path" ]]; then
                # Delete specific fleet
                delete_gamelift_fleet "$file_path" "false"
            else
                print_error "Fleet ID required for fleet deletion. Use --cleanup-file to specify fleet ID."
                return 1
            fi
            ;;
        "delete-all-fleets")
            # Delete all GameLift fleets
            delete_all_fleets "false"
            ;;
        "delete-fleet-force")
            # Force delete specific fleet (even with active computes)
            if [[ -n "$file_path" ]]; then
                delete_gamelift_fleet "$file_path" "true"
            else
                print_error "Fleet ID required for fleet deletion. Use --cleanup-file to specify fleet ID."
                return 1
            fi
            ;;
        "delete-all-fleets-force")
            # Force delete all GameLift fleets
            delete_all_fleets "true"
            ;;
        *)
            print_error "Invalid cleanup type: $cleanup_type"
            print_status "Valid cleanup types: auto, temp, file, env, all, output, fleet, delete-fleet, delete-all-fleets, delete-fleet-force, delete-all-fleets-force"
            return 1
            ;;
    esac
    
    print_success "Cleanup completed!"
}

# Main script
main() {
    # Default values
    INSTANCE_ID=""
    FLEET_ID=""
    LOCATION="custom-mygame-dev-location"
    AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    OUTPUT_DIR="./output"
    SKIP_REGISTRATION="false"
    COMPUTE_NAME=""
    DEBUG_MODE="false"
    CLEANUP_TYPE=""
    CLEANUP_FILE=""
    ENV_FORMATS=""
    
    # Check for environment variables
    if [[ -n "$GAMELIFT_FLEET_ID" ]]; then
        FLEET_ID="$GAMELIFT_FLEET_ID"
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--instance-id)
                INSTANCE_ID="$2"
                shift 2
                ;;
            -f|--fleet-id)
                FLEET_ID="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -o|--output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -s|--skip-registration)
                SKIP_REGISTRATION="true"
                shift
                ;;
            -c|--compute-name)
                COMPUTE_NAME="$2"
                shift 2
                ;;
            -d|--debug)
                DEBUG_MODE="true"
                shift
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
            --env-formats)
                ENV_FORMATS="$2"
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
        print_status "GameLift Game Server Setup Cleanup"
        cleanup "$CLEANUP_TYPE" "$CLEANUP_FILE"
        exit 0
    fi
    
    # Validate required parameters
    if [[ -z "$INSTANCE_ID" ]]; then
        print_error "Instance ID is required. Use -i or --instance-id option."
        show_usage
        exit 1
    fi
    
    if [[ "$SKIP_REGISTRATION" == "true" && -z "$COMPUTE_NAME" ]]; then
        print_error "Compute name is required when skipping registration. Use -c or --compute-name option."
        show_usage
        exit 1
    fi
    
    # Set up cleanup trap (only clean up files we create during this run)
    trap 'cleanup_temp_files' EXIT
    
    # Set AWS region
    export AWS_DEFAULT_REGION="$AWS_REGION"
    
    print_status "GameLift Anywhere Game Server Setup"
    print_status "Instance ID: $INSTANCE_ID"
    print_status "Fleet ID: $FLEET_ID"
    print_status "Location: $LOCATION"
    print_status "AWS Region: $AWS_REGION"
    print_status "Output Directory: $OUTPUT_DIR"
    print_status "Skip Registration: $SKIP_REGISTRATION"
    
    # Check prerequisites
    check_aws_cli
    check_aws_credentials
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install jq for JSON parsing."
        print_status "Installation: brew install jq (macOS) or sudo apt-get install jq (Ubuntu)"
        exit 1
    fi
    print_success "jq is available"
    
    # Handle fleet ID - create Anywhere fleet if needed
    if [[ -n "$FLEET_ID" ]]; then
        # Check if provided fleet is an Anywhere fleet
        if ! check_fleet_type "$FLEET_ID"; then
            print_warning "Provided fleet is not a GameLift Anywhere fleet"
            
            if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
                print_status "Automatically creating new GameLift Anywhere fleet (--yes flag)"
                local fleet_name="MyGame-Anywhere-Fleet-$(date +%Y%m%d-%H%M%S)"
                FLEET_ID=$(create_anywhere_fleet "$fleet_name" "$AWS_REGION")
                if [[ $? -ne 0 ]]; then
                    print_error "Failed to create GameLift Anywhere fleet"
                    exit 1
                fi
            else
                echo -n "Do you want to create a new GameLift Anywhere fleet? (y/N): "
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    # Generate fleet name based on instance
                    local fleet_name="MyGame-Anywhere-Fleet-$(date +%Y%m%d-%H%M%S)"
                    FLEET_ID=$(create_anywhere_fleet "$fleet_name" "$AWS_REGION")
                    if [[ $? -ne 0 ]]; then
                        print_error "Failed to create GameLift Anywhere fleet"
                        exit 1
                    fi
                else
                    print_error "Cannot proceed without a GameLift Anywhere fleet"
                    exit 1
                fi
            fi
        fi
    else
        # No fleet provided, create one automatically
        print_status "No fleet ID provided, creating a new GameLift Anywhere fleet"
        local fleet_name="MyGame-Anywhere-Fleet-$(date +%Y%m%d-%H%M%S)"
        FLEET_ID=$(create_anywhere_fleet "$fleet_name" "$AWS_REGION")
        if [[ $? -ne 0 ]]; then
            print_error "Failed to create GameLift Anywhere fleet"
            exit 1
        fi
    fi
    
    # Update the status display with the final fleet ID
    print_status "Using Fleet ID: $FLEET_ID"
    
    # Get instance information
    get_instance_info "$INSTANCE_ID"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Register compute or use existing one
    if [[ "$SKIP_REGISTRATION" == "false" ]]; then
        # Generate compute name
        COMPUTE_NAME=$(generate_compute_name "$INSTANCE_ID" "$INSTANCE_TYPE")
        print_status "Generated compute name: $COMPUTE_NAME"
        
        # Register compute
        REGISTERED_COMPUTE_NAME=$(run_register_compute "$FLEET_ID" "$COMPUTE_NAME" "$LOCATION" "$INSTANCE_PUBLIC_IP" "$AWS_REGION")
        COMPUTE_NAME="$REGISTERED_COMPUTE_NAME"
    else
        print_status "Skipping compute registration, using existing compute: $COMPUTE_NAME"
    fi
    
    # Generate auth token
    AUTH_TOKEN=$(run_generate_auth_token "$FLEET_ID" "$COMPUTE_NAME" "$AWS_REGION")
    
    # Create startup script
    STARTUP_SCRIPT="$OUTPUT_DIR/start_game_server.sh"
    create_startup_script "$FLEET_ID" "$COMPUTE_NAME" "$AUTH_TOKEN" "$INSTANCE_PUBLIC_IP" "$AWS_REGION" "$STARTUP_SCRIPT"
    
    # Generate environment variable files if requested
    if [[ -n "$ENV_FORMATS" ]]; then
        generate_env_files "$FLEET_ID" "$COMPUTE_NAME" "$AUTH_TOKEN" "$AWS_REGION" "$OUTPUT_DIR" "$ENV_FORMATS"
    fi
    
    # Create configuration summary
    CONFIG_FILE="$OUTPUT_DIR/gamelift_config.txt"
    cat > "$CONFIG_FILE" << EOF
GameLift Anywhere Configuration
==============================

Instance Information:
- Instance ID: $INSTANCE_ID
- Public IP: $INSTANCE_PUBLIC_IP
- Private IP: $INSTANCE_PRIVATE_IP
- Instance Type: $INSTANCE_TYPE
- Availability Zone: $INSTANCE_AZ

GameLift Configuration:
- Fleet ID: $FLEET_ID
- Compute Name: $COMPUTE_NAME
- Location: $LOCATION
- Region: $AWS_REGION
- Auth Token: $AUTH_TOKEN

Generated Files:
- Startup Script: $STARTUP_SCRIPT
- Config Summary: $CONFIG_FILE

EOF
    
    print_success "Game server setup completed!"
    echo ""
    print_status "Summary:"
    echo "  Instance ID: $INSTANCE_ID"
    echo "  Compute Name: $COMPUTE_NAME"
    echo "  Public IP: $INSTANCE_PUBLIC_IP"
    echo "  Fleet ID: $FLEET_ID"
    echo "  Location: $LOCATION"
    echo "  Auth Token: $AUTH_TOKEN"
    echo ""
    print_status "Generated files:"
    echo "  Startup Script: $STARTUP_SCRIPT"
    echo "  Config Summary: $CONFIG_FILE"
    if [[ -n "$ENV_FORMATS" ]]; then
        echo "  Environment Files:"
        IFS=',' read -ra format_array <<< "$ENV_FORMATS"
        for format in "${format_array[@]}"; do
            case $format in
                "env")
                    echo "    - $OUTPUT_DIR/gamelift.env"
                    ;;
                "json")
                    echo "    - $OUTPUT_DIR/gamelift_config.json"
                    ;;
                "yaml"|"yml")
                    echo "    - $OUTPUT_DIR/gamelift_config.yaml"
                    ;;
            esac
        done
    fi
    echo ""
    print_status "Next steps:"
    echo "  1. Copy the startup script to your EC2 instance"
    echo "  2. Ensure FPSTemplateServer is available"
    echo "  3. Run the startup script to begin GameLift integration"
    echo ""
    print_status "Quick start command:"
    echo "  scp $STARTUP_SCRIPT ec2-user@$INSTANCE_PUBLIC_IP:/local/game/"
    echo "  ssh ec2-user@$INSTANCE_PUBLIC_IP 'cd /local/game && ./start_game_server.sh'"
}

# Run main function
main "$@"
