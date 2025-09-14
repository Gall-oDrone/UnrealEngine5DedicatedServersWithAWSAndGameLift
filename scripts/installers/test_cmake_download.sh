#!/bin/bash

# Test CMake Download Script
# This script tests downloading CMake from S3 using SSM Document and Git raw URL

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/test_cmake_download.log"

# S3 Access Point configuration (same as deploy_installers_staged.sh)
S3_ACCESS_POINT_ARN="arn:aws:s3:us-east-1:123456789012:accesspoint/your-access-point-name"
AWS_REGION="us-east-1"

# CMake configuration
CMAKE_S3_KEY="CMake/Windows x86_64/Version 4.1.1/cmake-4.1.1-windows-x86_64.msi"

# SSM Document configuration
SSM_DOCUMENT_NAME="TestCMakeDownload"
SSM_DOCUMENT_URL="https://raw.githubusercontent.com/YOUR_REPO/ssm_doc_test_cmake_download.json"

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

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 <instance-id>

Test downloading CMake from S3 using SSM Document.

OPTIONS:
    -h, --help              Show this help message

EXAMPLES:
    $0 i-0a0cf65b6a9a9b7d0                    Test CMake download on instance

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
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_error "Please install the missing tools and try again"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to validate instance
validate_instance() {
    local instance_id="$1"
    
    print_info "Validating instance: $instance_id"
    
    # Verify instance exists and is running
    local instance_state=$(aws ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "not-found")
    
    if [ "$instance_state" = "not-found" ]; then
        print_error "Instance $instance_id not found or access denied"
        exit 1
    elif [ "$instance_state" != "running" ]; then
        print_error "Instance $instance_id is not running (current state: $instance_state)"
        exit 1
    fi
    
    # Check if SSM agent is available
    local ssm_status=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$instance_id" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo "Offline")
    
    if [ "$ssm_status" != "Online" ]; then
        print_error "SSM agent is not online on instance $instance_id (status: $ssm_status)"
        print_error "Please ensure SSM agent is installed and running"
        exit 1
    fi
    
    print_success "Instance validation passed"
    print_success "Instance ID: $instance_id"
    print_success "Instance State: $instance_state"
    print_success "SSM Status: $ssm_status"
}

# Function to create and register SSM document
create_ssm_document() {
    print_info "Creating SSM document from Git raw URL..."
    
    # Download the SSM document from Git
    local temp_doc="/tmp/${SSM_DOCUMENT_NAME}.json"
    
    print_info "Downloading SSM document from: $SSM_DOCUMENT_URL"
    
    if ! curl -s -o "$temp_doc" "$SSM_DOCUMENT_URL"; then
        print_error "Failed to download SSM document from Git"
        exit 1
    fi
    
    print_success "SSM document downloaded successfully"
    
    # Register the document with SSM
    print_info "Registering SSM document: $SSM_DOCUMENT_NAME"
    
    if aws ssm create-document \
        --name "$SSM_DOCUMENT_NAME" \
        --content "file://$temp_doc" \
        --document-type "Command" \
        --document-format "JSON" \
        --region "$AWS_REGION" > /dev/null; then
        print_success "SSM document registered successfully"
    else
        print_warning "SSM document might already exist, continuing..."
    fi
    
    # Clean up temp file
    rm -f "$temp_doc"
}

# Function to execute SSM document
execute_ssm_document() {
    local instance_id="$1"
    
    print_info "Executing SSM document on instance: $instance_id"
    
    # Execute the SSM document
    local command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "$SSM_DOCUMENT_NAME" \
        --parameters "bucketArn=$S3_ACCESS_POINT_ARN,objectKey=$CMAKE_S3_KEY,region=$AWS_REGION" \
        --region "$AWS_REGION" \
        --output text \
        --query 'Command.CommandId')
    
    if [ -z "$command_id" ]; then
        print_error "Failed to execute SSM document"
        exit 1
    fi
    
    print_success "Command ID: $command_id"
    log_message "INFO" "SSM document execution initiated with ID: $command_id"
    
    return "$command_id"
}

# Function to monitor command execution
monitor_execution() {
    local instance_id="$1"
    local command_id="$2"
    local max_wait=600  # 10 minutes
    
    local elapsed=0
    local interval=10
    
    print_info "⏳ Monitoring command execution..."
    
    while [ $elapsed -lt $max_wait ]; do
        # Check command status
        local status=$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" --query 'Status' --output text 2>/dev/null || echo "not-found")
        
        if [ "$status" = "not-found" ]; then
            print_error "Command not found or access denied"
            return 1
        fi
        
        case "$status" in
            "InProgress")
                if [ $((elapsed % 30)) -eq 0 ]; then
                    print_info "Command still in progress... ($elapsed seconds elapsed)"
                fi
                ;;
            "Success")
                print_success "✅ Command executed successfully!"
                
                # Get command output
                print_info "Command Output:"
                aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" --query 'StandardOutputContent' --output text
                
                return 0
                ;;
            "Failed"|"Cancelled"|"TimedOut")
                print_error "Command failed with status: $status"
                
                # Get error output
                print_error "Error Details:"
                aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" --query 'StandardErrorContent' --output text
                
                return 1
                ;;
            *)
                print_warning "Unknown status: $status"
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_warning "Timeout after $max_wait seconds"
    print_warning "Command might still be running. Check manually."
    
    return 1
}

# Function to cleanup SSM document
cleanup_ssm_document() {
    print_info "Cleaning up SSM document: $SSM_DOCUMENT_NAME"
    
    if aws ssm delete-document --name "$SSM_DOCUMENT_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
        print_success "SSM document deleted successfully"
    else
        print_warning "Failed to delete SSM document (might not exist)"
    fi
}

# Main execution function
main() {
    local instance_id=""
    
    # Initialize log file
    echo "Test CMake Download Log - $(date)" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$instance_id" ]; then
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
    
    if [ -z "$instance_id" ]; then
        print_error "Instance ID is required"
        show_usage
        exit 1
    fi
    
    print_info "�� Starting CMake Download Test"
    print_info "Instance ID: $instance_id"
    print_info "S3 Access Point ARN: $S3_ACCESS_POINT_ARN"
    print_info "CMake S3 Key: $CMAKE_S3_KEY"
    
    # Check prerequisites
    check_prerequisites
    
    # Validate instance
    validate_instance "$instance_id"
    
    # Create and register SSM document
    create_ssm_document
    
    # Execute SSM document
    local command_id=$(execute_ssm_document "$instance_id")
    
    # Monitor execution
    if monitor_execution "$instance_id" "$command_id"; then
        print_success "✅ CMake download test completed successfully!"
    else
        print_error "❌ CMake download test failed"
        exit 1
    fi
    
    # Cleanup
    cleanup_ssm_document
    
    print_success "✅ Test process completed!"
    print_info "Check the log file for detailed information: $LOG_FILE"
}

# Execute main function
main "$@"