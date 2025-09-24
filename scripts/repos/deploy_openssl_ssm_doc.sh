#!/bin/bash

# Deploy OpenSSL SSM Document Script
# This script deploys the OpenSSL build SSM document to AWS Systems Manager

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
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
LOG_FILE="$SCRIPT_DIR/openssl_ssm_deployment.log"

# Default values
ENVIRONMENT="dev"
REGION="us-east-1"
DOCUMENT_NAME="OpenSSL-Build-Windows"
AUTO_APPROVE=false

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

Deploy and execute OpenSSL build SSM document on Windows EC2 instances.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment (dev, staging, prod) [default: dev]
    -r, --region            AWS region [default: us-east-1]
    -n, --name              SSM document name [default: OpenSSL-Build-Windows]
    -a, --auto-approve      Auto-approve changes
    --update                Update existing document instead of creating new one
    --delete                Delete the SSM document
    --list                  List all SSM documents
    --validate              Validate JSON syntax only
    --register-only         Only register the SSM document, don't execute
    --verify-document       Verify SSM document is ready

REQUIRED:
    instance-id             EC2 instance ID to build OpenSSL on (unless using --register-only, --list, --validate, or --delete)

EXAMPLES:
    # Register and execute
    $0 i-0a0cf65b6a9a9b7d0                  Register document and build OpenSSL on instance
    $0 -a i-0a0cf65b6a9a9b7d0               Auto-approve and build OpenSSL
    
    # Document management only
    $0 --register-only                       Only register the SSM document
    $0 --verify-document                     Verify document is ready
    $0 --list                                List all documents
    $0 --validate                            Validate JSON syntax
    $0 --delete                              Delete the document

PREREQUISITES:
    1. Ensure the OpenSSL repository is cloned on the target instance
    2. Ensure Visual Studio Build Tools are installed
    3. Ensure Perl and NASM are installed
    4. Ensure the instance has SSM agent installed and running

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

# Function to validate JSON syntax
validate_json() {
    local json_file="$1"
    
    print_info "Validating JSON syntax for: $json_file"
    
    if ! jq empty "$json_file" 2>/dev/null; then
        print_error "Invalid JSON syntax in $json_file"
        jq . "$json_file" 2>&1 | head -10
        exit 1
    fi
    
    print_success "JSON syntax validation passed"
}

# Function to check if document exists
document_exists() {
    local doc_name="$1"
    local region="$2"
    
    aws ssm describe-document --name "$doc_name" --region "$region" &> /dev/null
}

# Function to deploy SSM document
deploy_document() {
    local json_file="$1"
    local doc_name="$2"
    local region="$3"
    local update_mode="$4"
    
    print_info "Deploying SSM document: $doc_name"
    print_info "Region: $region"
    print_info "JSON file: $json_file"
    
    # Check if document exists
    if document_exists "$doc_name" "$region"; then
        if [[ "$update_mode" == "true" ]]; then
            print_info "Updating existing document: $doc_name"
            aws ssm update-document \
                --name "$doc_name" \
                --content "file://$json_file" \
                --document-version "\$LATEST" \
                --region "$region" \
                --output table
            
            if [[ $? -eq 0 ]]; then
                print_success "✅ SSM document updated successfully: $doc_name"
            else
                print_error "❌ Failed to update SSM document: $doc_name"
                exit 1
            fi
        else
            print_warning "Document $doc_name already exists"
            print_info "Use --update flag to update the existing document"
            print_info "Or use --delete flag to remove it first"
            exit 1
        fi
    else
        print_info "Creating new document: $doc_name"
        aws ssm create-document \
            --name "$doc_name" \
            --content "file://$json_file" \
            --document-type "Command" \
            --document-format "JSON" \
            --region "$region" \
            --output table
        
        if [[ $? -eq 0 ]]; then
            print_success "✅ SSM document created successfully: $doc_name"
        else
            print_error "❌ Failed to create SSM document: $doc_name"
            exit 1
        fi
    fi
}

# Function to delete SSM document
delete_document() {
    local doc_name="$1"
    local region="$2"
    
    print_info "Deleting SSM document: $doc_name"
    
    if document_exists "$doc_name" "$region"; then
        aws ssm delete-document --name "$doc_name" --region "$region"
        
        if [[ $? -eq 0 ]]; then
            print_success "✅ SSM document deleted successfully: $doc_name"
        else
            print_error "❌ Failed to delete SSM document: $doc_name"
            exit 1
        fi
    else
        print_warning "Document $doc_name does not exist"
    fi
}

# Function to list SSM documents
list_documents() {
    local region="$1"
    
    print_info "Listing SSM documents in region: $region"
    
    aws ssm list-documents \
        --document-filter-list key=Owner,value=Self \
        --region "$region" \
        --query 'DocumentIdentifiers[?contains(Name, `OpenSSL`) || contains(Name, `openssl`)].{Name:Name,Description:Description,DocumentVersion:DocumentVersion}' \
        --output table
}

# Function to get document information
get_document_info() {
    local doc_name="$1"
    local region="$2"
    
    print_info "Getting document information for: $doc_name"
    
    aws ssm describe-document \
        --name "$doc_name" \
        --region "$region" \
        --query 'Document.{Name:Name,Description:Description,DocumentVersion:DocumentVersion,Status:Status,CreatedDate:CreatedDate}' \
        --output table
}

# Function to validate instance
validate_instance() {
    local instance_id="$1"
    
    print_info "Validating instance: $instance_id"
    
    # Verify instance exists and is running
    local instance_state=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "not-found")
    
    if [ "$instance_state" = "not-found" ]; then
        print_error "Instance $instance_id not found or access denied"
        exit 1
    elif [ "$instance_state" != "running" ]; then
        print_error "Instance $instance_id is not running (current state: $instance_state)"
        exit 1
    fi
    
    # Check if SSM agent is available
    local ssm_status=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$instance_id" \
        --region "$REGION" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "Offline")
    
    if [ "$ssm_status" != "Online" ]; then
        print_error "SSM agent is not online on instance $instance_id (status: $ssm_status)"
        print_error "Please ensure SSM agent is installed and running"
        exit 1
    fi
    
    # Get platform information
    local platform=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$instance_id" \
        --region "$REGION" \
        --query 'InstanceInformationList[0].PlatformType' \
        --output text 2>/dev/null || echo "Unknown")
    
    if [ "$platform" != "Windows" ]; then
        print_error "Instance platform: $platform (expected Windows)"
        print_error "This script is designed for Windows instances only"
        exit 1
    fi
    
    print_success "Instance validation passed"
    print_success "Instance ID: $instance_id"
    print_success "Instance State: $instance_state"
    print_success "SSM Status: $ssm_status"
    print_success "Platform: $platform"
}

# Function to execute OpenSSL build
execute_openssl_build() {
    local instance_id="$1"
    
    print_info "🚀 Starting OpenSSL build on instance: $instance_id"
    
    # Default parameters for OpenSSL build
    local openssl_repo_path="C:\\OpenSSL"
    local build_type="Release"
    local architecture="x64"
    local install_path="C:\\OpenSSL-Install"
    
    print_info "Build Parameters:"
    print_info "  Repository Path: $openssl_repo_path"
    print_info "  Build Type: $build_type"
    print_info "  Architecture: $architecture"
    print_info "  Install Path: $install_path"
    
    # Send command via SSM
    print_progress "Sending OpenSSL build command via SSM..."
    
    local command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "$DOCUMENT_NAME" \
        --parameters "opensslRepoPath=$openssl_repo_path,buildType=$build_type,architecture=$architecture,installPath=$install_path,region=$REGION" \
        --region "$REGION" \
        --timeout-seconds 3600 \
        --output text \
        --query 'Command.CommandId')
    
    if [ -z "$command_id" ]; then
        print_error "Failed to send OpenSSL build command"
        return 1
    fi
    
    print_success "Command ID: $command_id"
    log_message "INFO" "OpenSSL build command initiated with ID: $command_id"
    
    # Monitor the build process
    if monitor_openssl_build "$instance_id" "$command_id"; then
        print_success "✅ OpenSSL build completed successfully!"
        return 0
    else
        print_error "❌ OpenSSL build failed"
        return 1
    fi
}

# Function to monitor OpenSSL build progress
monitor_openssl_build() {
    local instance_id="$1"
    local command_id="$2"
    local max_wait=3600  # 60 minutes for OpenSSL build
    
    local elapsed=0
    local interval=15  # Check every 15 seconds
    local last_status=""
    
    print_progress "⏳ Monitoring OpenSSL build progress..."
    print_info "Command ID: $command_id"
    print_info "This may take up to 60 minutes..."
    
    while [ $elapsed -lt $max_wait ]; do
        # Get command status
        local status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --region "$REGION" \
            --query 'Status' \
            --output text 2>/dev/null || echo "Unknown")
        
        # Print status update only if changed
        if [ "$status" != "$last_status" ]; then
            print_progress "Status: $status"
            last_status="$status"
        fi
        
        case "$status" in
            "Success")
                print_success "✅ OpenSSL build completed successfully!"
                
                # Get command output
                print_info "\n📋 Build Output (last 20 lines):"
                aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --region "$REGION" \
                    --query 'StandardOutputContent' \
                    --output text | tail -20
                
                return 0
                ;;
            "Failed"|"Cancelled"|"TimedOut")
                print_error "OpenSSL build failed with status: $status"
                
                # Get error details
                print_error "\n❌ Error Details:"
                aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --region "$REGION" \
                    --query 'StandardErrorContent' \
                    --output text
                
                # Get standard output for additional context
                print_info "\n📋 Standard Output:"
                aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --region "$REGION" \
                    --query 'StandardOutputContent' \
                    --output text
                
                return 1
                ;;
            "InProgress"|"Pending"|"Delayed")
                if [ $((elapsed % 120)) -eq 0 ] && [ $elapsed -gt 0 ]; then
                    print_info "Still building... ($((elapsed/60)) minutes elapsed)"
                fi
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_warning "⏱️ Build timed out after $((max_wait/60)) minutes"
    print_warning "The build might still be running. Check manually using:"
    print_warning "aws ssm get-command-invocation --command-id $command_id --instance-id $instance_id --region $REGION"
    
    return 1
}

# Function to get instance connection information
get_connection_info() {
    local instance_id="$1"
    
    print_info "Getting instance connection information..."
    
    # Get instance details
    local instance_info=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].{PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress,Name:Tags[?Key==`Name`]|[0].Value,Platform:Platform}' \
        --output json)
    
    local public_ip=$(echo "$instance_info" | jq -r '.PublicIP // "N/A"')
    local private_ip=$(echo "$instance_info" | jq -r '.PrivateIP // "N/A"')
    local instance_name=$(echo "$instance_info" | jq -r '.Name // "Unnamed"')
    local platform=$(echo "$instance_info" | jq -r '.Platform // "linux"')
    
    print_success "\n📌 Instance Connection Information:"
    print_success "===================================="
    print_info "Instance Name: $instance_name"
    print_info "Instance ID: $instance_id"
    print_info "Public IP: $public_ip"
    print_info "Private IP: $private_ip"
    print_info "Platform: $platform"
    
    if [ "$platform" = "windows" ] || [ "$platform" = "Windows" ]; then
        if [ "$public_ip" != "N/A" ] && [ "$public_ip" != "null" ]; then
            print_info "RDP Connection: $public_ip:3389"
        else
            print_info "RDP Connection: $private_ip:3389 (via private network)"
        fi
    fi
}

# Main execution function
main() {
    local operation="deploy"
    local update_mode="false"
    local action="deploy"
    local instance_id=""
    local json_file="$SCRIPT_DIR/ssm/ssm_doc_build_openssl.json"
    
    # Initialize log file
    echo "OpenSSL SSM Document Deployment Log - $(date)" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -n|--name)
                DOCUMENT_NAME="$2"
                shift 2
                ;;
            -a|--auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --update)
                update_mode="true"
                shift
                ;;
            --delete)
                action="delete"
                shift
                ;;
            --list)
                action="list"
                shift
                ;;
            --validate)
                action="validate"
                shift
                ;;
            --register-only)
                action="register"
                shift
                ;;
            --verify-document)
                action="verify"
                shift
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
    
    print_info "🚀 OpenSSL SSM Document Script"
    print_info "Environment: $ENVIRONMENT"
    print_info "Region: $REGION"
    print_info "Document Name: $DOCUMENT_NAME"
    print_info "Action: $action"
    
    # Check prerequisites
    check_prerequisites
    
    # Check if JSON file exists (for actions that need it)
    if [[ "$action" == "deploy" || "$action" == "register" || "$action" == "validate" ]]; then
        if [[ ! -f "$json_file" ]]; then
            print_error "JSON file not found: $json_file"
            exit 1
        fi
    fi
    
    # Handle different actions
    case "$action" in
        "validate")
            print_info "📋 Validating JSON syntax..."
            validate_json "$json_file"
            print_success "✅ JSON validation completed successfully"
            exit 0
            ;;
        "register")
            print_info "📋 Registering SSM document..."
            validate_json "$json_file"
            deploy_document "$json_file" "$DOCUMENT_NAME" "$REGION" "$update_mode"
            get_document_info "$DOCUMENT_NAME" "$REGION"
            print_success "✅ SSM document registered successfully"
            exit 0
            ;;
        "verify")
            print_info "📋 Verifying SSM document..."
            if document_exists "$DOCUMENT_NAME" "$REGION"; then
                get_document_info "$DOCUMENT_NAME" "$REGION"
                print_success "✅ SSM document is ready"
            else
                print_error "❌ SSM document not found: $DOCUMENT_NAME"
                exit 1
            fi
            exit 0
            ;;
        "list")
            print_info "📋 Listing SSM documents..."
            list_documents "$REGION"
            exit 0
            ;;
        "delete")
            print_info "📋 Deleting SSM document..."
            delete_document "$DOCUMENT_NAME" "$REGION"
            exit 0
            ;;
        "deploy")
            # Continue with deployment logic
            if [ -z "$instance_id" ]; then
                print_error "Instance ID is required for deployment"
                show_usage
                exit 1
            fi
            
            print_info "Instance ID: $instance_id"
            
            # Validate JSON and register document if needed
            validate_json "$json_file"
            
            if ! document_exists "$DOCUMENT_NAME" "$REGION"; then
                print_warning "SSM document not found. Registering..."
                deploy_document "$json_file" "$DOCUMENT_NAME" "$REGION" "$update_mode"
            else
                print_success "SSM document found: $DOCUMENT_NAME"
            fi
            
            # Validate instance
            validate_instance "$instance_id"
            
            # Confirmation prompt (unless auto-approved)
            if [[ "$AUTO_APPROVE" != true ]]; then
                print_warning "\n⚠️  You are about to build OpenSSL on instance: $instance_id"
                print_warning "This process may take up to 60 minutes"
                echo -n "Do you want to continue? (yes/no): "
                read -r confirmation
                if [[ "$confirmation" != "yes" ]]; then
                    print_info "Operation cancelled by user"
                    exit 0
                fi
            fi
            
            # Execute OpenSSL build
            print_info "\n🔨 Starting OpenSSL build process..."
            if execute_openssl_build "$instance_id"; then
                print_success "\n✅ OpenSSL build completed successfully!"
            else
                print_error "\n❌ OpenSSL build failed"
                print_info "Check the logs on the instance: C:\\logs\\openssl-build-*.log"
            fi
            
            # Display connection information
            get_connection_info "$instance_id"
            ;;
        *)
            print_error "Unknown action: $action"
            show_usage
            exit 1
            ;;
    esac
    
    print_success "✅ OpenSSL SSM document operation completed!"
    print_info "Check the log file for detailed information: $LOG_FILE"
}

# Execute main function
main "$@"
