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
Usage: $0 [OPTIONS]

Deploy OpenSSL build SSM document to AWS Systems Manager.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment (dev, staging, prod) [default: dev]
    -r, --region            AWS region [default: us-east-1]
    -n, --name              SSM document name [default: OpenSSL-Build-Windows]
    --update                Update existing document instead of creating new one
    --delete                Delete the SSM document
    --list                  List all SSM documents
    --validate              Validate JSON syntax only

EXAMPLES:
    $0                                      Deploy with default settings
    $0 -e prod -r us-west-2                Deploy to production in us-west-2
    $0 --update                            Update existing document
    $0 --delete                            Delete the document
    $0 --list                              List all documents
    $0 --validate                          Validate JSON syntax

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

# Main execution function
main() {
    local operation="deploy"
    local update_mode="false"
    local json_file="$SCRIPT_DIR/ssm_doc_build_openssl.json"
    
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
            --update)
                update_mode="true"
                shift
                ;;
            --delete)
                operation="delete"
                shift
                ;;
            --list)
                operation="list"
                shift
                ;;
            --validate)
                operation="validate"
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                print_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    print_info "🚀 Starting OpenSSL SSM document operation"
    print_info "Environment: $ENVIRONMENT"
    print_info "Region: $REGION"
    print_info "Document Name: $DOCUMENT_NAME"
    print_info "Operation: $operation"
    
    # Check prerequisites
    check_prerequisites
    
    # Check if JSON file exists
    if [[ ! -f "$json_file" ]]; then
        print_error "JSON file not found: $json_file"
        exit 1
    fi
    
    case "$operation" in
        "validate")
            validate_json "$json_file"
            print_success "✅ JSON validation completed successfully"
            ;;
        "deploy")
            validate_json "$json_file"
            deploy_document "$json_file" "$DOCUMENT_NAME" "$REGION" "$update_mode"
            get_document_info "$DOCUMENT_NAME" "$REGION"
            ;;
        "delete")
            delete_document "$DOCUMENT_NAME" "$REGION"
            ;;
        "list")
            list_documents "$REGION"
            ;;
        *)
            print_error "Unknown operation: $operation"
            exit 1
            ;;
    esac
    
    print_success "✅ OpenSSL SSM document operation completed!"
    print_info "Check the log file for detailed information: $LOG_FILE"
}

# Execute main function
main "$@"
