#!/bin/bash

# Script to upload Unreal Engine builders to S3 bucket using SSM
# Author: Generated script for Unreal Engine 5 Dedicated Servers with AWS and GameLift

set -e  # Exit on any error

# Configuration
BUCKET_NAME="${BUCKET_NAME:-ue-builders-default}"
# If BUCKET_NAME is empty, use dynamic naming
if [ -z "$BUCKET_NAME" ]; then
    BUCKET_NAME="ue-builders-$(date +%s)-$$"
fi
AWS_REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSM_DOCUMENT_NAME="UploadUEBuildersToS3"

# Builder configuration arrays (similar to download_s3_installers.sh)
declare -a BUILDER_PATHS=(
    "C:\\UE5\\Builders\\MyGameBuilder"
    "C:\\UE5\\Builders\\AnotherGameBuilder"
    "C:\\UE5\\Builders\\ServerBuilder"
    # Add more builder paths here as needed
)

declare -a BUILDER_NAMES=(
    "MyGameBuilder"
    "AnotherGameBuilder"
    "ServerBuilder"
    # Add corresponding builder names here
)

declare -a BUILDER_S3_KEYS=(
    "builders/MyGameBuilder/"
    "builders/AnotherGameBuilder/"
    "builders/ServerBuilder/"
    # Add corresponding S3 keys here
)

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo "Error: AWS CLI is not installed. Please install it first."
        echo "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "Error: AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
}

# Function to create S3 bucket if it doesn't exist
create_bucket_if_not_exists() {
    echo "Checking if S3 bucket exists: $BUCKET_NAME"
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo "Bucket '$BUCKET_NAME' already exists."
    else
        echo "Creating S3 bucket: $BUCKET_NAME"
        
        # Create bucket
        if [ "$AWS_REGION" = "us-east-1" ]; then
            # us-east-1 doesn't need LocationConstraint
            aws s3api create-bucket --bucket "$BUCKET_NAME"
        else
            # Other regions need LocationConstraint
            aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --region "$AWS_REGION" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION"
        fi
        echo "Bucket '$BUCKET_NAME' created successfully."
    fi
}

# Function to validate builder paths
validate_builder_paths() {
    echo "Validating builder paths..."
    
    local valid_count=0
    local invalid_count=0
    
    for i in "${!BUILDER_PATHS[@]}"; do
        local path="${BUILDER_PATHS[$i]}"
        local name="${BUILDER_NAMES[$i]}"
        
        echo "Checking builder $((i+1)): $name"
        echo "  Path: $path"
        
        # Note: We can't actually validate Windows paths from Linux/Mac
        # This is just a placeholder for path validation
        echo "  ✓ Path configured (validation will occur on target instance)"
        ((valid_count++))
    done
    
    echo "Builder configuration validation complete: $valid_count builders configured"
    
    if [ ${#BUILDER_PATHS[@]} -eq 0 ]; then
        echo ""
        echo "Error: No builder paths configured in the script arrays."
        echo "Please edit the script to add your builder paths to the BUILDER_PATHS array."
        exit 1
    fi
}

# Function to create SSM document
create_ssm_document() {
    echo "Creating SSM document: $SSM_DOCUMENT_NAME"
    
    local ssm_doc_path="$SCRIPT_DIR/ssm/ssm_doc_upload_ue_builders.json"
    
    if [ ! -f "$ssm_doc_path" ]; then
        echo "Error: SSM document not found at: $ssm_doc_path"
        exit 1
    fi
    
    # Check if document already exists
    if aws ssm describe-document --name "$SSM_DOCUMENT_NAME" &>/dev/null; then
        echo "Updating existing SSM document: $SSM_DOCUMENT_NAME"
        aws ssm update-document \
            --name "$SSM_DOCUMENT_NAME" \
            --document-version "\$LATEST" \
            --content "file://$ssm_doc_path"
    else
        echo "Creating new SSM document: $SSM_DOCUMENT_NAME"
        aws ssm create-document \
            --name "$SSM_DOCUMENT_NAME" \
            --document-type "Command" \
            --content "file://$ssm_doc_path"
    fi
    
    echo "SSM document '$SSM_DOCUMENT_NAME' ready."
}

# Function to execute SSM document for a single builder
execute_builder_upload() {
    local builder_index="$1"
    local builder_path="${BUILDER_PATHS[$builder_index]}"
    local builder_name="${BUILDER_NAMES[$builder_index]}"
    local s3_key="${BUILDER_S3_KEYS[$builder_index]}"
    
    echo "Uploading builder $((builder_index+1)): $builder_name"
    echo "  Local Path: $builder_path"
    echo "  S3 Key: $s3_key"
    
    # Execute SSM command for this specific builder
    local execution_id
    execution_id=$(aws ssm send-command \
        --document-name "$SSM_DOCUMENT_NAME" \
        --targets "Key=tag:Name,Values=*" \
        --parameters "{
            \"bucketName\": [\"$BUCKET_NAME\"],
            \"s3Keys\": [\"$s3_key\"],
            \"builderNames\": [\"$builder_name\"],
            \"localPaths\": [\"$builder_path\"],
            \"region\": [\"$AWS_REGION\"]
        }" \
        --timeout-seconds 3600 \
        --region "$AWS_REGION" \
        --output text --query 'Command.CommandId')
    
    if [ $? -eq 0 ] && [ -n "$execution_id" ]; then
        echo "  ✅ SSM command sent successfully"
        echo "  Command ID: $execution_id"
        echo "  Monitor with: aws ssm get-command-invocation --command-id $execution_id --instance-id <instance-id>"
        return 0
    else
        echo "  ❌ Failed to send SSM command for $builder_name"
        return 1
    fi
}

# Function to execute all builder uploads
execute_all_builder_uploads() {
    echo "Executing builder uploads..."
    echo "Target bucket: $BUCKET_NAME"
    echo "Region: $AWS_REGION"
    echo "Total builders: ${#BUILDER_PATHS[@]}"
    echo ""
    
    local success_count=0
    local failure_count=0
    local execution_ids=()
    
    # Execute upload for each builder
    for i in "${!BUILDER_PATHS[@]}"; do
        echo "Processing builder $((i+1))/${#BUILDER_PATHS[@]}..."
        
        if execute_builder_upload "$i"; then
            ((success_count++))
            echo "  ✅ Upload initiated successfully"
        else
            ((failure_count++))
            echo "  ❌ Upload failed to initiate"
        fi
        
        echo ""
    done
    
    echo "Upload Summary:"
    echo "==============="
    echo "Total builders: ${#BUILDER_PATHS[@]}"
    echo "Successful initiations: $success_count"
    echo "Failed initiations: $failure_count"
    echo ""
    
    if [ $failure_count -eq 0 ]; then
        echo "✅ All builder uploads initiated successfully!"
        echo "Note: Actual uploads are performed by SSM on target instances."
        echo "Monitor progress using the provided command IDs."
        return 0
    else
        echo "⚠️  Some builder uploads failed to initiate."
        return 1
    fi
}

# Function to display bucket contents
display_bucket_contents() {
    echo ""
    echo "Bucket contents:"
    echo "=================="
    aws s3 ls "s3://${BUCKET_NAME}" --recursive --human-readable
}

# Function to display usage information
display_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Upload Unreal Engine builders to S3 bucket using AWS Systems Manager"
    echo ""
    echo "Note: Builder paths are configured in the script arrays (BUILDER_PATHS, BUILDER_NAMES, BUILDER_S3_KEYS)"
    echo ""
    echo "Options:"
    echo "  -h, --help       Show this help message"
    echo "  -b, --bucket     S3 bucket name (default: ue-builders-default)"
    echo "  -r, --region     AWS region (default: us-east-1)"
    echo "  -l, --list       List bucket contents after upload"
    echo "  --dry-run        Show what would be done without executing"
    echo "  --show-config    Show current builder configuration"
    echo ""
    echo "Environment Variables:"
    echo "  BUCKET_NAME      S3 bucket name (overrides -b option)"
    echo "  AWS_REGION       AWS region to use (overrides -r option)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Upload all configured builders"
    echo "  $0 --bucket my-ue-builders --region us-west-2"
    echo "  $0 --dry-run                          # Show what would be done"
    echo "  $0 --show-config                      # Show current configuration"
    echo "  BUCKET_NAME=my-builders $0            # Use environment variable"
}

# Function to show current configuration
show_configuration() {
    echo "Current Builder Configuration:"
    echo "=============================="
    echo "Bucket Name: $BUCKET_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "SSM Document: $SSM_DOCUMENT_NAME"
    echo "Total Builders: ${#BUILDER_PATHS[@]}"
    echo ""
    
    if [ ${#BUILDER_PATHS[@]} -eq 0 ]; then
        echo "⚠️  No builders configured. Please edit the script arrays."
        echo ""
        echo "Edit these arrays in the script:"
        echo "  BUILDER_PATHS    - Windows paths to builder directories"
        echo "  BUILDER_NAMES    - Friendly names for each builder"
        echo "  BUILDER_S3_KEYS  - S3 keys/paths for each builder"
        return 1
    fi
    
    echo "Configured Builders:"
    echo "--------------------"
    for i in "${!BUILDER_PATHS[@]}"; do
        echo "Builder $((i+1)):"
        echo "  Name: ${BUILDER_NAMES[$i]}"
        echo "  Path: ${BUILDER_PATHS[$i]}"
        echo "  S3 Key: ${BUILDER_S3_KEYS[$i]}"
        echo ""
    done
}

# Main function
main() {
    local list_contents=false
    local dry_run=false
    local show_config=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                display_usage
                exit 0
                ;;
            -b|--bucket)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -l|--list)
                list_contents=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --show-config)
                show_config=true
                shift
                ;;
            -*)
                echo "Unknown option: $1"
                display_usage
                exit 1
                ;;
            *)
                echo "Error: Unknown argument: $1"
                echo "This script doesn't accept positional arguments."
                echo "Configure builder paths in the script arrays instead."
                display_usage
                exit 1
                ;;
        esac
    done
    
    # Handle show-config option
    if [ "$show_config" = true ]; then
        show_configuration
        exit $?
    fi
    
    echo "Unreal Engine Builder Upload to S3"
    echo "==================================="
    echo "Bucket name: $BUCKET_NAME"
    echo "AWS region: $AWS_REGION"
    echo "Configured builders: ${#BUILDER_PATHS[@]}"
    echo ""
    
    # Show current configuration
    show_configuration
    echo ""
    
    if [ "$dry_run" = true ]; then
        echo "DRY RUN MODE - No actual operations will be performed"
        echo ""
        echo "Would perform the following actions:"
        echo "1. Check AWS CLI and credentials"
        echo "2. Create S3 bucket '$BUCKET_NAME' if it doesn't exist"
        echo "3. Validate builder configuration"
        echo "4. Create/update SSM document '$SSM_DOCUMENT_NAME'"
        echo "5. Execute SSM commands for each builder:"
        for i in "${!BUILDER_PATHS[@]}"; do
            echo "   - ${BUILDER_NAMES[$i]} (${BUILDER_PATHS[$i]} -> ${BUILDER_S3_KEYS[$i]})"
        done
        if [ "$list_contents" = true ]; then
            echo "6. List bucket contents"
        fi
        exit 0
    fi
    
    # Check prerequisites
    check_aws_cli
    check_aws_credentials
    
    # Create bucket if needed
    create_bucket_if_not_exists
    
    # Validate builder configuration
    validate_builder_paths
    
    # Create SSM document
    create_ssm_document
    
    # Execute all builder uploads
    execute_all_builder_uploads
    
    echo ""
    echo "Upload process initiated successfully!"
    echo "Bucket URL: https://s3.console.aws.amazon.com/s3/buckets/${BUCKET_NAME}"
    echo ""
    echo "Note: The actual upload will be performed by the SSM document on the target instances."
    echo "Make sure your target instances have the necessary IAM permissions to access the S3 bucket."
    
    if [ "$list_contents" = true ]; then
        display_bucket_contents
    fi
}

# Run main function with all arguments
main "$@"
