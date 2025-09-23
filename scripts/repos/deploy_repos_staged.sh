#!/bin/bash

# Staged Repository Deployment Script for Windows EC2 via SSM
# This script uses the Repository-Operations-Windows SSM document to manage repositories

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
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
LOG_FILE="$SCRIPT_DIR/repo_deployment.log"

# Default values
ENVIRONMENT="dev"
REGION="us-east-1"
AUTO_APPROVE=false
SKIP_REPO_CHECK=false
SSM_DOCUMENT_NAME="Repository-Operations-Windows"

# SSM Document configuration
SSM_DOCS_DIR="$SCRIPT_DIR/ssm"
SSM_DOC_FILE="ssm_doc_repo_operations.json"

# Array of repository URLs (you can modify these as needed)
declare -a REPO_URLS=(
    "https://github.com/amazon-gamelift/amazon-gamelift-plugin-unreal.git"
    "https://github.com/openssl/openssl.git"
)

# Array of repository names (corresponding to REPO_URLS array)
declare -a REPO_NAMES=(
    "Amazon GameLift Plugin for Unreal Engine"
    "OpenSSL"
)

# Array of repository branches (corresponding to REPO_URLS array)
declare -a REPO_BRANCHES=(
    "main"
    "master"
)

# Array of destination directories (corresponding to REPO_URLS array)
declare -a REPO_DESTINATIONS=(
    "C:\\AmazonGameLiftPlugin"
    "C:\\OpenSSL"
)

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

Clone repositories to Windows EC2 instances using SSM document.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to deploy (dev, staging, prod) [default: dev]
    -r, --region            AWS region [default: us-east-1]
    -a, --auto-approve      Auto-approve changes
    --skip-repo-check       Skip repository connectivity check
    -l, --list-repos        List configured repositories
    --add-repo              Add a new repository URL interactively
    --update-repos          Update existing repositories
    --pull-repos            Pull latest changes for existing repositories
    --ssm-doc-name          SSM document name [default: Repository-Operations-Windows]
    
    SSM Document Management:
    --register-document     Register/update the SSM document (always creates new version)
    --verify-document       Verify SSM document is ready
    --list-documents        List existing SSM documents
    --cleanup-document      Delete the SSM document

EXAMPLES:
    # Repository operations
    $0 i-0a0cf65b6a9a9b7d0                    Clone repositories to instance
    $0 -a i-0a0cf65b6a9a9b7d0                 Clone with auto-approval
    $0 --skip-repo-check i-0a0cf65b6a9a9b7d0  Clone without checking repository URLs
    $0 -l                                      List configured repositories
    $0 --add-repo                              Add new repository interactively
    $0 --update-repos i-0a0cf65b6a9a9b7d0     Update existing repositories
    $0 --pull-repos i-0a0cf65b6a9a9b7d0       Pull latest changes
    
    # SSM Document management
    $0 --register-document                     Register/update SSM document
    $0 --verify-document                       Verify SSM document is ready
    $0 --list-documents                        List existing SSM documents
    $0 --cleanup-document                      Delete SSM document

PREREQUISITES:
    1. Register the SSM document first:
       $0 --register-document
    
    2. Ensure Git is installed on the target Windows instance
    
    3. Ensure the instance has SSM agent installed and running

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

# Function to check if SSM document exists
check_ssm_document() {
    local doc_name="$1"
    local region="$2"
    
    print_info "Checking if SSM document exists: $doc_name"
    
    if aws ssm describe-document --name "$doc_name" --region "$region" &> /dev/null; then
        print_success "SSM document found: $doc_name"
        return 0
    else
        print_error "SSM document not found: $doc_name"
        print_error "Please register the SSM document first using:"
        print_error "  $0 --register-document"
        return 1
    fi
}

# Function to verify SSM document
verify_ssm_document() {
    local doc_name="$1"
    
    print_info "Verifying SSM document: $doc_name"
    
    # Check if document exists - capture both stdout and stderr separately
    local doc_info
    local error_output
    
    doc_info=$(aws ssm describe-document \
        --name "$doc_name" \
        --region "$REGION" \
        --output json 2>/tmp/ssm_verify_error.txt)
    
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        error_output=$(cat /tmp/ssm_verify_error.txt 2>/dev/null || echo "Unknown error")
        print_error "Document does not exist or is not accessible"
        print_error "Error: $error_output"
        rm -f /tmp/ssm_verify_error.txt
        return 1
    fi
    
    rm -f /tmp/ssm_verify_error.txt
    
    # Validate JSON before parsing
    if ! echo "$doc_info" | jq empty 2>/dev/null; then
        print_error "Invalid JSON response from AWS CLI"
        print_error "Response: $doc_info"
        return 1
    fi
    
    # Parse document info
    local doc_status=$(echo "$doc_info" | jq -r '.Document.Status // "Unknown"' 2>/dev/null || echo "Unknown")
    local doc_type=$(echo "$doc_info" | jq -r '.Document.DocumentType // "Unknown"' 2>/dev/null || echo "Unknown")
    local doc_version=$(echo "$doc_info" | jq -r '.Document.DocumentVersion // "Unknown"' 2>/dev/null || echo "Unknown")
    
    print_info "Document Status: $doc_status"
    print_info "Document Type: $doc_type"
    print_info "Document Version: $doc_version"
    
    if [[ "$doc_status" != "Active" ]]; then
        print_error "Document is not active (status: $doc_status)"
        return 1
    fi
    
    print_success "Document verified successfully"
    return 0
}

# Function to register/update SSM document (always creates new version)
register_ssm_document() {
    print_info "Registering/updating SSM document: $SSM_DOCUMENT_NAME (always creates new version)"
    
    # Define path to SSM document JSON file
    local doc_file="$SSM_DOCS_DIR/$SSM_DOC_FILE"
    
    # Check if document file exists
    if [[ ! -f "$doc_file" ]]; then
        print_error "SSM document file not found: $doc_file"
        print_info "Please ensure $SSM_DOC_FILE exists in: $SSM_DOCS_DIR"
        return 1
    fi
    
    print_success "Found SSM document file: $doc_file"
    
    # Validate JSON structure
    if ! jq empty "$doc_file" 2>/dev/null; then
        print_error "SSM document file has invalid JSON"
        print_info "You can validate it with: jq . $doc_file"
        return 1
    fi
    
    print_success "JSON validation passed"
    
    # Always delete existing document to ensure new version
    print_progress "Checking for existing document..."
    local existing_doc
    existing_doc=$(aws ssm describe-document \
        --name "$SSM_DOCUMENT_NAME" \
        --region "$REGION" \
        --output json 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        print_info "Document already exists, deleting to create new version..."
        
        # Delete existing document
        if aws ssm delete-document \
            --name "$SSM_DOCUMENT_NAME" \
            --region "$REGION" 2>/tmp/ssm_delete_error.txt; then
            print_success "Old document deleted"
            sleep 3  # Wait for deletion to propagate
        else
            local delete_error=$(cat /tmp/ssm_delete_error.txt 2>/dev/null)
            print_warning "Could not delete old document: $delete_error"
            rm -f /tmp/ssm_delete_error.txt
        fi
    else
        print_info "No existing document found"
    fi
    
    # Create new document
    print_progress "Creating new SSM document..."
    local create_output
    create_output=$(aws ssm create-document \
        --name "$SSM_DOCUMENT_NAME" \
        --document-type "Command" \
        --content "file://$doc_file" \
        --document-format "JSON" \
        --region "$REGION" \
        --output json 2>/tmp/ssm_create_error.txt)
    
    local create_exit_code=$?
    
    if [[ $create_exit_code -eq 0 ]]; then
        # Validate JSON response before parsing
        if echo "$create_output" | jq empty 2>/dev/null; then
            local doc_status=$(echo "$create_output" | jq -r '.DocumentDescription.Status // "Unknown"')
            local doc_version=$(echo "$create_output" | jq -r '.DocumentDescription.DocumentVersion // "Unknown"')
            
            print_success "✅ Created: $SSM_DOCUMENT_NAME"
            print_info "Created with status: $doc_status, version: $doc_version"
        else
            print_success "✅ Document created (could not parse response)"
        fi
        
        # Wait for document to become active
        print_progress "Waiting for document to become active..."
        sleep 5
        
        # Verify document
        if verify_ssm_document "$SSM_DOCUMENT_NAME"; then
            print_success "Document is ready to use"
        else
            print_warning "Document created but verification failed - it may need more time to propagate"
        fi
        
        rm -f /tmp/ssm_create_error.txt
        return 0
    else
        local create_error=$(cat /tmp/ssm_create_error.txt 2>/dev/null || echo "Unknown error")
        print_error "❌ Failed to create: $SSM_DOCUMENT_NAME"
        print_error "Error: $create_error"
        
        # Check if it's a validation error
        if echo "$create_error" | grep -q "ValidationException"; then
            print_error "Document has validation errors. Please check the JSON structure."
            print_info "Document file: $doc_file"
            print_info "You can validate it with: jq . $doc_file"
        fi
        
        rm -f /tmp/ssm_create_error.txt
        return 1
    fi
}

# Function to cleanup SSM document
cleanup_ssm_document() {
    print_info "🧹 Cleaning up SSM document: $SSM_DOCUMENT_NAME"
    
    # Check if document exists
    if aws ssm describe-document --name "$SSM_DOCUMENT_NAME" --region "$REGION" &>/dev/null; then
        print_progress "Deleting SSM document: $SSM_DOCUMENT_NAME"
        
        if aws ssm delete-document \
            --name "$SSM_DOCUMENT_NAME" \
            --region "$REGION" 2>/tmp/ssm_delete_error.txt; then
            print_success "✅ Deleted: $SSM_DOCUMENT_NAME"
            rm -f /tmp/ssm_delete_error.txt
            return 0
        else
            local delete_error=$(cat /tmp/ssm_delete_error.txt 2>/dev/null || echo "Unknown error")
            print_error "❌ Failed to delete $SSM_DOCUMENT_NAME: $delete_error"
            rm -f /tmp/ssm_delete_error.txt
            return 1
        fi
    else
        print_info "Document not found: $SSM_DOCUMENT_NAME"
        return 0
    fi
}

# Function to list SSM documents
list_ssm_documents() {
    print_info "Listing SSM documents matching: $SSM_DOCUMENT_NAME"
    
    # List all Command documents if specific one not found
    local docs
    docs=$(aws ssm list-documents \
        --document-filter-list "key=DocumentType,value=Command" \
        --region "$REGION" \
        --output json 2>/tmp/ssm_list_error.txt)
    
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        local error_output=$(cat /tmp/ssm_list_error.txt 2>/dev/null || echo "Unknown error")
        print_error "Failed to list documents: $error_output"
        rm -f /tmp/ssm_list_error.txt
        return 1
    fi
    
    rm -f /tmp/ssm_list_error.txt
    
    # Validate JSON before parsing
    if ! echo "$docs" | jq empty 2>/dev/null; then
        print_error "Invalid JSON response from AWS CLI"
        return 1
    fi
    
    # Check for our specific document
    local our_doc=$(echo "$docs" | jq --arg name "$SSM_DOCUMENT_NAME" '.DocumentIdentifiers[] | select(.Name == $name)' 2>/dev/null)
    
    if [[ -n "$our_doc" ]]; then
        print_success "Found document: $SSM_DOCUMENT_NAME"
        echo "$our_doc" | jq -r '"  - Name: \(.Name)\n  - Version: \(.DocumentVersion)\n  - Owner: \(.Owner)\n  - Platform: \(.PlatformTypes // ["N/A"] | join(", "))"'
    else
        print_warning "Document not found: $SSM_DOCUMENT_NAME"
        
        # Show recent Command documents for reference
        print_info "Recent Command documents in account:"
        echo "$docs" | jq -r '.DocumentIdentifiers[:5][] | "  - \(.Name) (Owner: \(.Owner))"' 2>/dev/null || echo "  No documents found"
    fi
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
        print_warning "Instance platform: $platform (expected Windows)"
        print_warning "This script is designed for Windows instances"
    fi
    
    print_success "Instance validation passed"
    print_success "Instance ID: $instance_id"
    print_success "Instance State: $instance_state"
    print_success "SSM Status: $ssm_status"
    print_success "Platform: $platform"
}

# Function to list configured repositories
list_repos() {
    print_info "Configured Repositories:"
    print_info "======================="
    
    if [ ${#REPO_URLS[@]} -eq 0 ]; then
        print_warning "No repositories configured"
        print_info "Use --add-repo to add repositories interactively"
        return 0
    fi
    
    for i in "${!REPO_URLS[@]}"; do
        local url="${REPO_URLS[$i]}"
        local name="${REPO_NAMES[$i]:-Unnamed}"
        local branch="${REPO_BRANCHES[$i]:-main}"
        local destination="${REPO_DESTINATIONS[$i]:-C:\Repos\$name}"
        
        echo "  [$((i+1))] $name"
        echo "      URL: $url"
        echo "      Branch: $branch"
        echo "      Destination: $destination"
        echo ""
    done
}

# Function to add repository interactively
add_repo() {
    print_info "Adding new repository..."
    
    echo -n "Enter repository name: "
    read -r repo_name
    
    echo -n "Enter repository URL: "
    read -r repo_url
    
    echo -n "Enter branch name [main]: "
    read -r repo_branch
    repo_branch=${repo_branch:-main}
    
    echo -n "Enter destination directory [D:\\Repos\\$repo_name]: "
    read -r repo_destination
    repo_destination=${repo_destination:-"D:\\Repos\\$repo_name"}
    
    # Validate URL
    if [[ ! "$repo_url" =~ ^https?://.*\.git$ ]]; then
        print_warning "URL doesn't end with .git, but continuing..."
    fi
    
    # Add to arrays
    REPO_URLS+=("$repo_url")
    REPO_NAMES+=("$repo_name")
    REPO_BRANCHES+=("$repo_branch")
    REPO_DESTINATIONS+=("$repo_destination")
    
    print_success "Repository added successfully"
    print_info "Name: $repo_name"
    print_info "URL: $repo_url"
    print_info "Branch: $repo_branch"
    print_info "Destination: $repo_destination"
    
    print_warning "Note: To persist this repository, you need to manually add it to the script arrays"
}

# Function to validate repository URLs
validate_repo_urls() {
    if [ ${#REPO_URLS[@]} -eq 0 ]; then
        print_warning "No repositories configured"
        return 0
    fi
    
    print_info "Validating repository URLs..."
    
    for i in "${!REPO_URLS[@]}"; do
        local url="${REPO_URLS[$i]}"
        local name="${REPO_NAMES[$i]:-Unnamed}"
        
        if [ -z "$url" ]; then
            print_warning "Skipping empty URL for repository: $name"
            continue
        fi
        
        print_info "Checking: $name"
        
        # Test URL accessibility (basic check)
        if curl -s --head "$url" --connect-timeout 5 | head -n 1 | grep -q "HTTP"; then
            print_success "✅ $name - URL is accessible"
        else
            print_warning "⚠️ $name - URL might not be accessible or is private"
        fi
    done
}

# Function to deploy repositories via SSM document
deploy_repos() {
    local instance_id="$1"
    local operation="$2"  # clone, update, pull
    
    print_info "Deploying repositories to instance: $instance_id (operation: $operation)"
    
    local success_count=0
    local failure_count=0
    local total_repos=${#REPO_URLS[@]}
    
    # Process each repository individually
    for i in "${!REPO_URLS[@]}"; do
        local repo_url="${REPO_URLS[$i]}"
        local repo_name="${REPO_NAMES[$i]}"
        local repo_branch="${REPO_BRANCHES[$i]}"
        local repo_destination="${REPO_DESTINATIONS[$i]}"
        
        # Skip empty URLs
        if [ -z "$repo_url" ]; then
            print_warning "Skipping empty URL at index $i"
            continue
        fi
        
        print_info "Processing repository $((i+1))/$total_repos: $repo_name"
        print_info "  URL: $repo_url"
        print_info "  Branch: $repo_branch"
        print_info "  Destination: $repo_destination"
        
        # Send command via SSM for this single repository
        print_info "Sending $operation command for $repo_name via SSM..."
        
        local command_id=$(aws ssm send-command \
            --instance-ids "$instance_id" \
            --document-name "$SSM_DOCUMENT_NAME" \
            --parameters "repoUrl=$repo_url,repoName=$repo_name,repoBranch=$repo_branch,repoDestination=$repo_destination,operation=$operation" \
            --region "$REGION" \
            --output text \
            --query 'Command.CommandId')
        
        if [ -z "$command_id" ]; then
            print_error "Failed to send command for $repo_name"
            failure_count=$((failure_count + 1))
            continue
        fi
        
        print_success "Command ID for $repo_name: $command_id"
        log_message "INFO" "Repository $operation command for $repo_name initiated with ID: $command_id"
        
        # Monitor this single repository operation
        if monitor_single_repo "$instance_id" "$command_id" "$repo_name"; then
            print_success "✅ $repo_name $operation completed successfully"
            success_count=$((success_count + 1))
        else
            print_error "❌ $repo_name $operation failed"
            failure_count=$((failure_count + 1))
        fi
        
        # Small delay between repositories
        sleep 2
    done
    
    # Final summary
    print_info ""
    print_info "=========================================="
    print_info "Repository Operations Summary"
    print_info "=========================================="
    print_info "Total repositories: $total_repos"
    print_info "✅ Successful: $success_count"
    print_info "❌ Failed: $failure_count"
    print_info "=========================================="
    
    if [ $failure_count -eq 0 ]; then
        print_success "All repository operations completed successfully!"
        return 0
    elif [ $success_count -gt 0 ]; then
        print_warning "Some repository operations failed"
        return 1
    else
        print_error "All repository operations failed"
        return 1
    fi
}

# Function to monitor single repository operation
monitor_single_repo() {
    local instance_id="$1"
    local command_id="$2"
    local repo_name="$3"
    local max_wait=${4:-600}  # Default 10 minutes for single repo
    
    local elapsed=0
    local interval=10  # Check every 10 seconds
    
    print_info "⏳ Monitoring $repo_name operation..."
    print_info "Command ID: $command_id"
    
    while [ $elapsed -lt $max_wait ]; do
        # Check command status
        local status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --region "$REGION" \
            --query 'Status' \
            --output text 2>/dev/null || echo "not-found")
        
        if [ "$status" = "not-found" ]; then
            print_error "Command not found or access denied"
            return 1
        fi
        
        case "$status" in
            "InProgress"|"Pending")
                if [ $((elapsed % 30)) -eq 0 ]; then
                    print_progress "$repo_name operation in progress... ($((elapsed / 60)) minutes elapsed)"
                fi
                ;;
            "Success")
                print_success "✅ $repo_name operation completed successfully!"
                return 0
                ;;
            "Failed"|"Cancelled"|"TimedOut")
                print_error "$repo_name operation failed with status: $status"
                
                # Get error output
                local error_output=$(aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --region "$REGION" \
                    --query 'StandardErrorContent' \
                    --output text 2>/dev/null || echo "")
                
                if [ -n "$error_output" ]; then
                    print_error "Error details: $error_output"
                fi
                
                return 1
                ;;
            *)
                print_warning "Unknown status for $repo_name: $status"
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_warning "Timeout after $((max_wait / 60)) minutes for $repo_name"
    return 1
}

# Function to monitor repository operations progress (legacy - for backward compatibility)
monitor_repos() {
    local instance_id="$1"
    local command_id="$2"
    local max_wait=${3:-1800}  # Default 30 minutes
    
    local elapsed=0
    local interval=10  # Check every 10 seconds initially
    local detailed_interval=30  # Show detailed progress every 30 seconds
    
    print_info "⏳ Monitoring repository operations progress..."
    print_info "Command ID: $command_id"
    
    while [ $elapsed -lt $max_wait ]; do
        # Check command status
        local status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --region "$REGION" \
            --query 'Status' \
            --output text 2>/dev/null || echo "not-found")
        
        if [ "$status" = "not-found" ]; then
            print_error "Command not found or access denied"
            return 1
        fi
        
        case "$status" in
            "InProgress"|"Pending")
                if [ $((elapsed % detailed_interval)) -eq 0 ]; then
                    print_progress "Repository operations in progress... ($((elapsed / 60)) minutes elapsed)"
                    
                    # Try to get partial output
                    local partial_output=$(aws ssm get-command-invocation \
                        --command-id "$command_id" \
                        --instance-id "$instance_id" \
                        --region "$REGION" \
                        --query 'StandardOutputContent' \
                        --output text 2>/dev/null || echo "")
                    
                    if [ -n "$partial_output" ]; then
                        echo "$partial_output" | tail -5
                    fi
                fi
                ;;
            "Success")
                print_success "✅ Repository operations completed successfully!"
                
                # Get command output
                print_info "\n📋 Repository Operations Output:"
                print_info "================================"
                aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --region "$REGION" \
                    --query 'StandardOutputContent' \
                    --output text
                
                return 0
                ;;
            "Failed"|"Cancelled"|"TimedOut")
                print_error "Repository operations failed with status: $status"
                
                # Get error output
                print_error "\n❌ Error Details:"
                print_error "================="
                aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --region "$REGION" \
                    --query 'StandardErrorContent' \
                    --output text
                
                # Get standard output for additional context
                print_info "\n📋 Standard Output:"
                print_info "=================="
                aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --region "$REGION" \
                    --query 'StandardOutputContent' \
                    --output text
                
                return 1
                ;;
            *)
                print_warning "Unknown status: $status"
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
        
        # Increase interval after first minute to reduce API calls
        if [ $elapsed -gt 60 ] && [ $interval -lt 30 ]; then
            interval=30
        fi
    done
    
    print_warning "⏱️ Timeout after $((max_wait / 60)) minutes"
    print_warning "Operations might still be running. Check manually using:"
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
    local instance_id=""
    local operation="clone"
    local action="deploy"
    
    # Initialize log file
    echo "Repository Deployment Log - $(date)" > "$LOG_FILE"
    
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
            -a|--auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --skip-repo-check)
                SKIP_REPO_CHECK=true
                shift
                ;;
            -l|--list-repos)
                list_repos
                exit 0
                ;;
            --add-repo)
                add_repo
                exit 0
                ;;
            --update-repos)
                operation="update"
                shift
                ;;
            --pull-repos)
                operation="pull"
                shift
                ;;
            --ssm-doc-name)
                SSM_DOCUMENT_NAME="$2"
                shift 2
                ;;
            --register-document)
                action="register"
                shift
                ;;
            --verify-document)
                action="verify"
                shift
                ;;
            --list-documents)
                action="list"
                shift
                ;;
            --cleanup-document)
                action="cleanup"
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
    
    print_info "🚀 Repository Deployment Script"
    print_info "Environment: $ENVIRONMENT"
    print_info "Region: $REGION"
    print_info "SSM Document: $SSM_DOCUMENT_NAME"
    print_info "Action: $action"
    
    # Check prerequisites
    check_prerequisites
    
    # Handle different actions
    case "$action" in
        "register")
            print_info "📋 Registering/updating SSM document..."
            if register_ssm_document; then
                print_success "✅ SSM document registered successfully"
                exit 0
            else
                print_error "❌ Failed to register SSM document"
                exit 1
            fi
            ;;
        "verify")
            print_info "📋 Verifying SSM document..."
            if verify_ssm_document "$SSM_DOCUMENT_NAME"; then
                print_success "✅ SSM document is ready"
                exit 0
            else
                print_error "❌ SSM document verification failed"
                exit 1
            fi
            ;;
        "list")
            print_info "📋 Listing SSM documents..."
            list_ssm_documents
            exit $?
            ;;
        "cleanup")
            print_info "📋 Cleaning up SSM document..."
            if cleanup_ssm_document; then
                print_success "✅ SSM document cleaned up successfully"
                exit 0
            else
                print_error "❌ Failed to cleanup SSM document"
                exit 1
            fi
            ;;
        "deploy")
            # Continue with deployment logic
            if [ -z "$instance_id" ]; then
                print_error "Instance ID is required for deployment"
                show_usage
                exit 1
            fi
            
            print_info "Instance ID: $instance_id"
            print_info "Operation: $operation"
            
            # Check if SSM document exists
            if ! check_ssm_document "$SSM_DOCUMENT_NAME" "$REGION"; then
                print_warning "SSM document not found. Attempting to register..."
                if register_ssm_document; then
                    print_success "SSM document registered successfully"
                else
                    print_error "Failed to register SSM document"
                    exit 1
                fi
            fi
            ;;
        *)
            print_error "Unknown action: $action"
            show_usage
            exit 1
            ;;
    esac
    
    # Only continue with deployment if action is "deploy"
    if [[ "$action" == "deploy" ]]; then
        # Validate instance
        validate_instance "$instance_id"
        
        # List configured repositories
        list_repos
        
        if [ ${#REPO_URLS[@]} -eq 0 ]; then
            print_warning "No repositories configured. Use --add-repo to add repositories."
            exit 0
        fi
        
        # Validate repository URLs (unless skipped)
        if [[ "$SKIP_REPO_CHECK" != true ]]; then
            validate_repo_urls
        fi
        
        # Confirmation prompt (unless auto-approved)
        if [[ "$AUTO_APPROVE" != true ]]; then
            print_warning "\n⚠️  You are about to $operation ${#REPO_URLS[@]} repositories"
            print_warning "Target instance: $instance_id"
            echo -n "Do you want to continue? (yes/no): "
            read -r confirmation
            if [[ "$confirmation" != "yes" ]]; then
                print_info "Operation cancelled by user"
                exit 0
            fi
        fi
        
        # Deploy repositories (includes monitoring)
        print_info "\n📦 Starting repository $operation process..."
        if deploy_repos "$instance_id" "$operation"; then
            print_success "\n✅ All repository operations completed successfully!"
        else
            print_warning "\n⚠️ Some repository operations may have issues. Check logs on the instance:"
            print_warning "   C:\\logs\\repo-operations-*.log"
        fi
        
        # Display connection information
        get_connection_info "$instance_id"
        
        print_success "\n✅ Repository deployment process completed!"
        print_info "Log file: $LOG_FILE"
        print_info "To check logs on the instance, look in: C:\\logs\\"
    fi
}

# Execute main function
main "$@"