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
INSTANCE_ID="${INSTANCE_ID:-}"  # Instance ID for SSM execution

# Builder configuration arrays (similar to download_s3_installers.sh)
declare -a BUILDER_PATHS=(
    "D:/UE_5_6_Projects/UnrealEngine5DedicatedServersWithAWSAndGameLift/gameTemplate/FPSTemplate_5_6/Builds/Windows/Build_01/Server/WindowsServer/FPSTemplate"
    # Add more builder paths here as needed
)

declare -a BUILDER_NAMES=(
    "Binaries.zip"
    # Add corresponding builder names here
)

declare -a BUILDER_S3_KEYS=(
    "builders/Windows/Server/FPSTemplate/"
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

# Function to validate instance ID
validate_instance_id() {
    if [ -z "$INSTANCE_ID" ]; then
        echo ""
        echo "Error: No instance ID provided."
        echo "Please specify an instance ID using one of the following methods:"
        echo "  1. Use the -i or --instance-id flag"
        echo "  2. Set the INSTANCE_ID environment variable"
        echo ""
        echo "Example:"
        echo "  $0 --instance-id i-1234567890abcdef0"
        echo "  INSTANCE_ID=i-1234567890abcdef0 $0"
        echo ""
        exit 1
    fi
    
    echo "Validating instance ID: $INSTANCE_ID"
    
    # Check if instance exists and is running
    local instance_state
    instance_state=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to describe instance $INSTANCE_ID"
        echo "Response: $instance_state"
        exit 1
    fi
    
    echo "Instance state: $instance_state"
    
    if [ "$instance_state" != "running" ]; then
        echo "Warning: Instance is not in 'running' state. Current state: $instance_state"
        echo "The SSM command may not execute successfully."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check if SSM agent is online
    echo "Checking SSM agent connectivity..."
    local ping_status
    ping_status=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>&1)
    
    if [ $? -ne 0 ] || [ "$ping_status" == "None" ] || [ -z "$ping_status" ]; then
        echo "Error: SSM agent is not responding on instance $INSTANCE_ID"
        echo "Please ensure:"
        echo "  1. SSM agent is installed and running on the instance"
        echo "  2. Instance has proper IAM role with SSM permissions"
        echo "  3. Instance has network connectivity to SSM endpoints"
        exit 1
    fi
    
    echo "✓ SSM agent status: $ping_status"
    echo "✓ Instance validation successful"
    echo ""
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
        ((valid_count++)) || true  # Prevent exit on increment failure
    done
    
    echo "Builder configuration validation complete: $valid_count builders configured"
    echo ""
    
    if [ ${#BUILDER_PATHS[@]} -eq 0 ]; then
        echo "Error: No builder paths configured in the script arrays."
        echo "Please edit the script to add your builder paths to the BUILDER_PATHS array."
        exit 1
    fi
    
    return 0
}

# Function to create or update SSM document
create_ssm_document() {
    echo "Preparing SSM document: $SSM_DOCUMENT_NAME"
    
    local ssm_doc_path="$SCRIPT_DIR/ssm/ssm_doc_upload_ue_builders.json"
    
    if [ ! -f "$ssm_doc_path" ]; then
        echo "Error: SSM document not found at: $ssm_doc_path"
        echo "Expected path: $ssm_doc_path"
        exit 1
    fi
    
    echo "SSM document template found: $ssm_doc_path"
    
    # Check if document already exists
    if aws ssm describe-document --name "$SSM_DOCUMENT_NAME" --region "$AWS_REGION" &>/dev/null; then
        echo "SSM document exists - creating new version..."
        
        # Update document (creates a new version)
        local update_output
        if update_output=$(aws ssm update-document \
            --name "$SSM_DOCUMENT_NAME" \
            --document-version "\$LATEST" \
            --content "file://$ssm_doc_path" \
            --region "$AWS_REGION" 2>&1); then
            
            # Extract new version number
            local new_version
            new_version=$(echo "$update_output" | grep -o '"DocumentVersion": "[^"]*"' | cut -d'"' -f4)
            
            echo "✓ SSM document updated successfully"
            echo "  New version: $new_version"
            
            # Set the new version as default
            echo "  Setting version $new_version as default..."
            if aws ssm update-document-default-version \
                --name "$SSM_DOCUMENT_NAME" \
                --document-version "$new_version" \
                --region "$AWS_REGION" &>/dev/null; then
                echo "  ✓ Default version updated to $new_version"
            else
                echo "  ⚠️  Warning: Could not set default version (non-critical)"
            fi
        else
            echo "Error: Failed to update SSM document"
            echo "$update_output"
            exit 1
        fi
    else
        echo "Creating new SSM document: $SSM_DOCUMENT_NAME"
        if aws ssm create-document \
            --name "$SSM_DOCUMENT_NAME" \
            --document-type "Command" \
            --content "file://$ssm_doc_path" \
            --region "$AWS_REGION" 2>&1; then
            echo "✓ SSM document created successfully (version 1)"
        else
            echo "Error: Failed to create SSM document"
            exit 1
        fi
    fi
    
    echo "SSM document '$SSM_DOCUMENT_NAME' ready."
    echo ""
    return 0
}

# Function to delete SSM document
delete_ssm_document() {
    echo "Deleting SSM document: $SSM_DOCUMENT_NAME"
    echo "Region: $AWS_REGION"
    echo ""
    
    # Check if document exists
    if ! aws ssm describe-document --name "$SSM_DOCUMENT_NAME" --region "$AWS_REGION" &>/dev/null; then
        echo "✓ SSM document does not exist (nothing to delete)"
        return 0
    fi
    
    # Get document info
    echo "Document found. Retrieving details..."
    local doc_info
    doc_info=$(aws ssm describe-document \
        --name "$SSM_DOCUMENT_NAME" \
        --region "$AWS_REGION" 2>&1)
    
    if [ $? -eq 0 ]; then
        local owner
        owner=$(echo "$doc_info" | grep -o '"Owner": "[^"]*"' | cut -d'"' -f4)
        local version_count
        version_count=$(aws ssm list-document-versions \
            --name "$SSM_DOCUMENT_NAME" \
            --region "$AWS_REGION" \
            --query 'length(DocumentVersions)' \
            --output text 2>/dev/null || echo "unknown")
        
        echo "  Owner: $owner"
        echo "  Versions: $version_count"
    fi
    
    echo ""
    read -p "Are you sure you want to delete this SSM document? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deletion cancelled."
        return 0
    fi
    
    echo "Deleting SSM document..."
    if aws ssm delete-document \
        --name "$SSM_DOCUMENT_NAME" \
        --region "$AWS_REGION" 2>&1; then
        echo "✓ SSM document deleted successfully"
        echo ""
        echo "To recreate the document, run the script normally:"
        echo "  $0 --instance-id <INSTANCE_ID>"
        return 0
    else
        echo "✗ Failed to delete SSM document"
        echo "This may happen if:"
        echo "  1. Document doesn't exist"
        echo "  2. Document is owned by AWS (cannot delete AWS-owned documents)"
        echo "  3. You don't have ssm:DeleteDocument permission"
        return 1
    fi
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
    echo "  Target Instance: $INSTANCE_ID"
    
    # Execute SSM command for this specific builder
    local execution_id
    execution_id=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "$SSM_DOCUMENT_NAME" \
        --parameters "{
            \"bucketName\": [\"$BUCKET_NAME\"],
            \"s3Keys\": [\"$s3_key\"],
            \"builderNames\": [\"$builder_name\"],
            \"localPaths\": [\"$builder_path\"],
            \"region\": [\"$AWS_REGION\"]
        }" \
        --timeout-seconds 3600 \
        --region "$AWS_REGION" \
        --output text --query 'Command.CommandId' 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$execution_id" ] && [[ "$execution_id" != *"error"* ]]; then
        echo "  ✅ SSM command sent successfully"
        echo "  Command ID: $execution_id"
        
        # Monitor the command execution
        monitor_builder_upload "$execution_id" "$builder_name"
        return $?
    else
        echo "  ❌ Failed to send SSM command for $builder_name"
        echo "  Error: $execution_id"
        return 1
    fi
}

# Function to monitor builder upload progress
monitor_builder_upload() {
    local command_id="$1"
    local builder_name="$2"
    
    echo ""
    echo "Monitoring upload progress for: $builder_name"
    echo "Command ID: $command_id"
    echo "This may take several minutes depending on builder size..."
    echo ""
    
    local max_attempts=120  # 120 attempts * 5 seconds = 10 minutes max
    local attempt=0
    local status=""
    
    while [ $attempt -lt $max_attempts ]; do
        # Get command invocation status
        local result
        result=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$INSTANCE_ID" \
            --region "$AWS_REGION" \
            --output json 2>&1)
        
        if [ $? -eq 0 ]; then
            status=$(echo "$result" | grep -o '"Status": "[^"]*"' | head -1 | cut -d'"' -f4)
            
            case "$status" in
                "Success")
                    echo "  ✅ Upload completed successfully!"
                    echo ""
                    echo "Command output:"
                    echo "$result" | grep -A 50 '"StandardOutputContent"' | sed 's/\\n/\n/g' | head -30
                    return 0
                    ;;
                "Failed")
                    echo "  ❌ Upload failed"
                    echo ""
                    echo "Error output:"
                    echo "$result" | grep -A 50 '"StandardErrorContent"' | sed 's/\\n/\n/g' | head -30
                    return 1
                    ;;
                "InProgress"|"Pending")
                    # Show progress indicator
                    echo -ne "  ⏳ Upload in progress... (attempt $attempt/$max_attempts)\r"
                    ;;
                *)
                    echo "  ⚠️  Unknown status: $status"
                    ;;
            esac
        else
            echo "  ⚠️  Failed to get command status (attempt $attempt)"
        fi
        
        sleep 5
        ((attempt++))
    done
    
    echo ""
    echo "  ⚠️  Timeout waiting for upload to complete"
    echo "  Check command status manually with:"
    echo "  aws ssm get-command-invocation --command-id $command_id --instance-id $INSTANCE_ID"
    return 1
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
            ((success_count++)) || true
            echo "  ✅ Upload completed successfully"
        else
            ((failure_count++)) || true
            echo "  ❌ Upload failed"
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
    echo "  -h, --help                    Show this help message"
    echo "  -i, --instance-id INSTANCE_ID EC2 instance ID for SSM execution (REQUIRED for upload)"
    echo "  -b, --bucket                  S3 bucket name (default: ue-builders-default)"
    echo "  -r, --region                  AWS region (default: us-east-1)"
    echo "  -l, --list                    List bucket contents after upload"
    echo "  --dry-run                     Show what would be done without executing"
    echo "  --show-config                 Show current builder configuration"
    echo "  --clean, --delete-document    Delete the SSM document"
    echo ""
    echo "Environment Variables:"
    echo "  INSTANCE_ID      EC2 instance ID (overrides -i option)"
    echo "  BUCKET_NAME      S3 bucket name (overrides -b option)"
    echo "  AWS_REGION       AWS region to use (overrides -r option)"
    echo ""
    echo "Examples:"
    echo "  # Upload builders"
    echo "  $0 --instance-id i-1234567890abcdef0"
    echo "  $0 -i i-1234567890abcdef0 --bucket my-ue-builders --region us-west-2"
    echo ""
    echo "  # Configuration and testing"
    echo "  $0 --show-config"
    echo "  $0 -i i-1234567890abcdef0 --dry-run"
    echo ""
    echo "  # Cleanup"
    echo "  $0 --clean                    # Delete SSM document"
    echo "  $0 --delete-document          # Same as --clean"
    echo ""
    echo "  # Environment variables"
    echo "  INSTANCE_ID=i-1234567890abcdef0 $0"
    echo ""
    echo "Prerequisites:"
    echo "  1. Target EC2 instance must be running"
    echo "  2. SSM Agent must be installed and running on the instance"
    echo "  3. Instance must have IAM role with SSM and S3 permissions"
    echo "  4. Instance must have AWS CLI installed"
    echo "  5. Builder directories must exist on the target instance"
    echo ""
    echo "Notes:"
    echo "  - The SSM document is automatically updated to a new version on each run"
    echo "  - Old versions are retained for audit/rollback purposes"
    echo "  - Use --clean to delete the SSM document and all its versions"
}

# Function to show current configuration
show_configuration() {
    echo "Current Builder Configuration:"
    echo "=============================="
    echo "Instance ID: ${INSTANCE_ID:-<not set>}"
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
    local clean_document=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                display_usage
                exit 0
                ;;
            -i|--instance-id)
                INSTANCE_ID="$2"
                shift 2
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
            --clean|--delete-document)
                clean_document=true
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
    
    # Handle cleanup option first
    if [ "$clean_document" = true ]; then
        echo "SSM Document Cleanup"
        echo "===================="
        echo ""
        check_aws_cli
        check_aws_credentials
        delete_ssm_document
        exit $?
    fi
    
    # Handle show-config option
    if [ "$show_config" = true ]; then
        show_configuration
        exit $?
    fi
    
    echo "Unreal Engine Builder Upload to S3"
    echo "==================================="
    echo "Instance ID: ${INSTANCE_ID:-<not set>}"
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
        echo "2. Validate instance ID: ${INSTANCE_ID:-<not set>}"
        echo "3. Create S3 bucket '$BUCKET_NAME' if it doesn't exist"
        echo "4. Validate builder configuration"
        echo "5. Create/update SSM document '$SSM_DOCUMENT_NAME'"
        echo "6. Execute SSM commands for each builder:"
        for i in "${!BUILDER_PATHS[@]}"; do
            echo "   - ${BUILDER_NAMES[$i]} (${BUILDER_PATHS[$i]} -> ${BUILDER_S3_KEYS[$i]})"
        done
        if [ "$list_contents" = true ]; then
            echo "7. List bucket contents"
        fi
        exit 0
    fi
    
    # Check prerequisites
    check_aws_cli
    check_aws_credentials
    
    # Validate instance ID (REQUIRED)
    validate_instance_id
    
    # Create bucket if needed
    create_bucket_if_not_exists
    
    # Validate builder configuration
    validate_builder_paths
    
    # Create SSM document
    create_ssm_document
    
    # Execute all builder uploads
    execute_all_builder_uploads
    
    echo ""
    echo "Upload process completed!"
    echo "Bucket URL: https://s3.console.aws.amazon.com/s3/buckets/${BUCKET_NAME}"
    echo ""
    
    if [ "$list_contents" = true ]; then
        display_bucket_contents
    fi
}

# Run main function with all arguments
main "$@"
