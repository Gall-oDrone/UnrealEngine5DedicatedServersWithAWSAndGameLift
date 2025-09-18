#!/bin/bash

# Debug CMake Download Script
# Simplified script to debug CMake download from S3 access point

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/cmake_debug_$(date +%Y%m%d_%H%M%S).log"

# Default values
AWS_REGION="${AWS_REGION:-us-east-1}"

# S3 Access Point configuration
S3_ACCESS_POINT_ARN="${S3_ACCESS_POINT_ARN:-arn:aws:s3:us-east-1:326105557351:accesspoint/test-ap-2}"

# SSM Document name for debugging
SSM_DOC_DEBUG="DebugCMakeDownload"

# CMake configuration
CMAKE_S3_KEY="CMake/Windows x86_64/Version 4.1.1/cmake-4.1.1-windows-x86_64.msi"
CMAKE_NAME="CMake"
CMAKE_DESTINATION="C:\\downloads\\cmake"

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_message "INFO" "$1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_message "SUCCESS" "$1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_message "WARNING" "$1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_message "ERROR" "$1"
}

print_progress() {
    echo -e "${CYAN}[PROGRESS]${NC} $1"
    log_message "PROGRESS" "$1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] <instance-id>

Debug CMake Download Script
Simplified script to debug CMake download from S3 access point.

OPTIONS:
    -h, --help              Show this help message
    -r, --region            AWS region [default: us-east-1]
    --register-document     Register debug SSM document
    --status                Check download status

REQUIRED:
    instance-id             EC2 instance ID to download CMake to

EXAMPLES:
    $0 i-0abc123def456789                     Download CMake
    $0 --register-document                    Register SSM document
    $0 --status i-0abc123def456789            Check download status

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Please install: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
        print_error "AWS credentials not configured or expired"
        print_info "Please run: aws configure"
        exit 1
    fi
    
    # Get account info
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    local caller_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    
    print_success "Prerequisites check passed"
    print_info "AWS Account: $account_id"
    print_info "Caller: $caller_arn"
    print_info "Region: $AWS_REGION"
}

# Function to validate instance
validate_instance() {
    local instance_id="$1"
    
    print_info "Validating instance: $instance_id"
    
    # Check instance exists and is running
    local instance_info=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].{State:State.Name,Platform:Platform,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}' \
        --output json 2>/dev/null || echo "{}")
    
    if [[ "$instance_info" == "{}" ]]; then
        print_error "Instance $instance_id not found"
        return 1
    fi
    
    local state=$(echo "$instance_info" | jq -r '.State')
    local platform=$(echo "$instance_info" | jq -r '.Platform // "linux"')
    local private_ip=$(echo "$instance_info" | jq -r '.PrivateIp')
    local public_ip=$(echo "$instance_info" | jq -r '.PublicIp // "N/A"')
    
    if [[ "$state" != "running" ]]; then
        print_error "Instance is not running (state: $state)"
        return 1
    fi
    
    if [[ "$platform" != "windows" ]]; then
        print_error "Instance is not Windows (platform: $platform)"
        print_info "This script is designed for Windows instances only"
        return 1
    fi
    
    # Check SSM agent status
    local ssm_info=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$instance_id" \
        --region "$AWS_REGION" \
        --query 'InstanceInformationList[0].{PingStatus:PingStatus,Platform:PlatformType,Version:PlatformVersion}' \
        --output json 2>/dev/null || echo "{}")
    
    if [[ "$ssm_info" == "{}" ]] || [[ "$ssm_info" == "null" ]]; then
        print_error "SSM Agent not found or not running on instance"
        print_info "Please ensure SSM Agent is installed and running"
        return 1
    fi
    
    local ssm_status=$(echo "$ssm_info" | jq -r '.PingStatus // "Unknown"')
    
    if [[ "$ssm_status" != "Online" ]]; then
        print_error "SSM Agent is not online (status: $ssm_status)"
        return 1
    fi
    
    print_success "Instance validation passed"
    print_info "Instance ID: $instance_id"
    print_info "State: $state"
    print_info "Platform: $platform"
    print_info "Private IP: $private_ip"
    print_info "Public IP: $public_ip"
    print_info "SSM Status: $ssm_status"
    
    return 0
}

# Function to validate S3 object
validate_s3_object() {
    print_info "Validating S3 object: $CMAKE_S3_KEY"
    
    # Check if object exists using head-object
    if aws s3api head-object \
        --bucket "$S3_ACCESS_POINT_ARN" \
        --key "$CMAKE_S3_KEY" \
        --region "$AWS_REGION" &>/dev/null; then
        
        # Get object metadata
        local object_info=$(aws s3api head-object \
            --bucket "$S3_ACCESS_POINT_ARN" \
            --key "$CMAKE_S3_KEY" \
            --region "$AWS_REGION" \
            --output json)
        
        local size=$(echo "$object_info" | jq -r '.ContentLength // 0')
        local size_mb=$((size / 1024 / 1024))
        local last_modified=$(echo "$object_info" | jq -r '.LastModified // "Unknown"')
        
        print_success "✅ CMake object - Valid (${size_mb}MB, Modified: $last_modified)"
        return 0
    else
        print_error "❌ CMake object - Not found or not accessible"
        return 1
    fi
}

# Function to register SSM document
register_ssm_document() {
    print_info "Registering debug SSM document: $SSM_DOC_DEBUG"
    
    local doc_file="$SCRIPT_DIR/ssm_doc_download_cmake_debug.json"
    
    if [[ ! -f "$doc_file" ]]; then
        print_error "SSM document file not found: $doc_file"
        return 1
    fi
    
    # Check if document already exists
    if aws ssm describe-document \
        --name "$SSM_DOC_DEBUG" \
        --region "$AWS_REGION" &>/dev/null; then
        print_warning "Document already exists, updating..."
        
        # Update existing document
        if aws ssm update-document \
            --name "$SSM_DOC_DEBUG" \
            --content "file://$doc_file" \
            --document-version "\$LATEST" \
            --region "$AWS_REGION" &>/dev/null; then
            print_success "✅ Updated: $SSM_DOC_DEBUG"
        else
            print_error "❌ Failed to update: $SSM_DOC_DEBUG"
            return 1
        fi
    else
        # Create new document
        if aws ssm create-document \
            --name "$SSM_DOC_DEBUG" \
            --document-type "Command" \
            --content "file://$doc_file" \
            --document-format "JSON" \
            --region "$AWS_REGION" &>/dev/null; then
            print_success "✅ Created: $SSM_DOC_DEBUG"
        else
            print_error "❌ Failed to create: $SSM_DOC_DEBUG"
            return 1
        fi
    fi
    
    print_success "SSM document registration complete"
}

# Function to download CMake
download_cmake() {
    local instance_id="$1"
    
    print_info "📦 Downloading CMake from S3..."
    
    # Debug: Print parameter values
    print_info "Parameters being sent:"
    print_info "  S3BucketArn: $S3_ACCESS_POINT_ARN"
    print_info "  SoftwareKey: $CMAKE_S3_KEY"
    print_info "  SoftwareName: $CMAKE_NAME"
    print_info "  DownloadPath: $CMAKE_DESTINATION"
    print_info "  Region: $AWS_REGION"
    
    # Execute download SSM document
    print_progress "Executing download command..."
    
    local command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "$SSM_DOC_DEBUG" \
        --parameters "{
            \"s3BucketArn\": [\"$S3_ACCESS_POINT_ARN\"],
            \"softwareKey\": [\"$CMAKE_S3_KEY\"],
            \"softwareName\": [\"$CMAKE_NAME\"],
            \"downloadPath\": [\"$CMAKE_DESTINATION\"],
            \"region\": [\"$AWS_REGION\"]
        }" \
        --timeout-seconds 1800 \
        --region "$AWS_REGION" \
        --output text \
        --query 'Command.CommandId')
    
    if [[ -z "$command_id" ]]; then
        print_error "Failed to send download command"
        return 1
    fi
    
    print_info "Download command ID: $command_id"
    
    # Monitor download progress
    if monitor_command "$instance_id" "$command_id" "download"; then
        print_success "✅ CMake download completed successfully"
        return 0
    else
        print_error "❌ CMake download failed"
        return 1
    fi
}

# Function to monitor SSM command execution
monitor_command() {
    local instance_id="$1"
    local command_id="$2"
    local operation="$3"
    local max_wait=1800  # 30 minutes
    
    local elapsed=0
    local interval=10
    local last_status=""
    
    print_progress "⏳ Monitoring $operation..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        # Get command status
        local command_info=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --region "$AWS_REGION" \
            --output json 2>/dev/null || echo "{}")
        
        if [[ "$command_info" == "{}" ]]; then
            print_warning "Command not found yet, waiting..."
            sleep $interval
            elapsed=$((elapsed + interval))
            continue
        fi
        
        local status=$(echo "$command_info" | jq -r '.Status // "Unknown"')
        
        # Print status update only if changed
        if [[ "$status" != "$last_status" ]]; then
            print_progress "Status: $status"
            last_status="$status"
        fi
        
        case "$status" in
            Success)
                # Get output
                local output=$(echo "$command_info" | jq -r '.StandardOutputContent // ""' | tail -20)
                if [[ -n "$output" ]]; then
                    echo "Output (last 20 lines):"
                    echo "$output"
                fi
                return 0
                ;;
            Failed|TimedOut|Cancelled|AccessDenied|DeliveryTimedOut)
                # Get error details
                local error_output=$(echo "$command_info" | jq -r '.StandardErrorContent // ""')
                if [[ -n "$error_output" ]]; then
                    print_error "Error details:"
                    echo "$error_output"
                fi
                return 1
                ;;
            InProgress|Pending|Delayed)
                if [[ $((elapsed % 60)) -eq 0 ]] && [[ $elapsed -gt 0 ]]; then
                    print_info "Still $status... ($((elapsed/60)) minutes elapsed)"
                fi
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_warning "Operation timed out after $((max_wait/60)) minutes"
    return 1
}

# Function to check download status
check_download_status() {
    local instance_id="$1"
    
    print_info "Checking CMake download status..."
    
    # Check for downloaded file
    local check_command=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=[
            "if (Test-Path \"C:\\downloads\\cmake\\cmake-4.1.1-windows-x86_64.msi\") {",
            "    $file = Get-Item \"C:\\downloads\\cmake\\cmake-4.1.1-windows-x86_64.msi\"",
            "    $sizeMB = [math]::Round($file.Length / 1MB, 2)",
            "    \"CMake downloaded successfully - Size: $sizeMB MB - Created: $($file.CreationTime)\"",
            "} else {",
            "    \"CMake not found in C:\\downloads\\cmake\\\"",
            "}"
        ]' \
        --region "$AWS_REGION" \
        --output text \
        --query 'Command.CommandId')
    
    if [[ -n "$check_command" ]]; then
        sleep 5
        
        local result=$(aws ssm get-command-invocation \
            --command-id "$check_command" \
            --instance-id "$instance_id" \
            --region "$AWS_REGION" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "Check failed")
        
        print_info "Download Status:"
        echo "$result"
    fi
}

# Main execution function
main() {
    local instance_id=""
    local action="download"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            --register-document)
                action="register"
                shift
                ;;
            --status)
                action="status"
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$instance_id" ]]; then
                    instance_id="$1"
                else
                    print_error "Multiple instance IDs provided"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    print_info "🚀 Debug CMake Download Script"
    print_info "Region: $AWS_REGION"
    print_info "S3 Access Point: $S3_ACCESS_POINT_ARN"
    print_info "CMake S3 Key: $CMAKE_S3_KEY"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Handle different actions
    if [[ "$action" == "register" ]]; then
        register_ssm_document
        exit 0
    fi
    
    # Validate instance ID
    if [[ -z "$instance_id" ]]; then
        print_error "Instance ID is required"
        show_usage
        exit 1
    fi
    
    # Validate instance
    if ! validate_instance "$instance_id"; then
        print_error "Instance validation failed"
        exit 1
    fi
    
    if [[ "$action" == "status" ]]; then
        check_download_status "$instance_id"
        exit 0
    fi
    
    # Validate S3 object
    print_info "📋 Validating S3 object..."
    if ! validate_s3_object; then
        print_error "S3 validation failed"
        exit 1
    fi
    
    # Register SSM document
    print_info "📋 Registering SSM document..."
    if ! register_ssm_document; then
        print_error "SSM document registration failed"
        exit 1
    fi
    
    # Download CMake
    print_info "📥 Downloading CMake..."
    if download_cmake "$instance_id"; then
        print_success "✅ CMake download completed"
    else
        print_error "❌ CMake download failed"
        exit 1
    fi
    
    # Final status check
    print_info "📊 Final Status Check..."
    check_download_status "$instance_id"
    
    print_success "✅ Debug CMake Download workflow complete!"
    print_info "Log file: $LOG_FILE"
}

# Execute main function
main "$@"
