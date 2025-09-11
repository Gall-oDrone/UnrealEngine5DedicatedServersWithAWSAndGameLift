#!/bin/bash

# Script to create S3 bucket 'installers' with folder structure for storing installers
# Author: Generated script for Unreal Engine 5 Dedicated Servers with AWS and GameLift

set -e  # Exit on any error

# Configuration
BUCKET_NAME="${BUCKET_NAME:-installers-1757543545-28881}"
# If BUCKET_NAME is empty, use dynamic naming
if [ -z "$BUCKET_NAME" ]; then
    BUCKET_NAME="installers-$(date +%s)-$$"
fi
AWS_REGION="${AWS_REGION:-us-east-1}"

# Array of S3 folder paths (you can modify these as needed)
declare -a S3_PATHS=(
    "Python Manager/Windows x86_64/Version 25.0b14"
    "Strawberry Perl/Windows x86_64/Version 5.40.2.1"
    "NASM/Windows x86_64/Version 2.16.03"
    "Git/Windows x86_64/Version 2.51.0"
    # Add more paths here as needed
)

# Array of installer URLs (corresponding to S3_PATHS array)
# Empty string means no installer to download for that path
declare -a INSTALLER_URLS=(
    "https://www.python.org/ftp/python/pymanager/python-manager-25.0b14.msi" # Python Manager installer
    "https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54021_64bit_UCRT/strawberry-perl-5.40.2.1-64bit.msi" # Strawberry Perl installer
    "https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/win64/nasm-2.16.03-installer-x64.exe" # NASM installer
    "https://github.com/git-for-windows/git/releases/download/v2.51.0.windows.1/Git-2.51.0-64-bit.exe" # Git installer
    # Add more URLs here as needed
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

# Function to create S3 bucket
create_bucket() {
    echo "Creating S3 bucket: $BUCKET_NAME"
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo "Bucket '$BUCKET_NAME' already exists."
    else
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

# Function to create folder structure in S3
create_folder_structure() {
    echo "Creating folder structure in S3 bucket..."
    
    for i in "${!S3_PATHS[@]}"; do
        local s3_path="${S3_PATHS[$i]}"
        local installer_url="${INSTALLER_URLS[$i]}"
        
        echo "Processing path: $s3_path"
        
        # Create folder structure by uploading an empty object
        # S3 doesn't have real folders, but we can create a placeholder
        local folder_key="${s3_path}/.folder_placeholder"
        echo "" | aws s3api put-object \
            --bucket "$BUCKET_NAME" \
            --key "$folder_key" \
            --content-type "application/x-directory"
        
        # If installer URL is provided, download and upload the installer
        if [ -n "$installer_url" ]; then
            echo "  Downloading installer from: $installer_url"
            
            # Extract filename from URL
            local filename=$(basename "$installer_url")
            local installer_key="${s3_path}/${filename}"
            
            # Download installer to temporary location
            local temp_file="/tmp/${filename}"
            curl -L -o "$temp_file" "$installer_url"
            
            # Upload to S3
            aws s3 cp "$temp_file" "s3://${BUCKET_NAME}/${installer_key}"
            
            # Clean up temporary file
            rm -f "$temp_file"
            
            echo "  Uploaded installer to: s3://${BUCKET_NAME}/${installer_key}"
        else
            echo "  No installer URL provided for this path (left empty as requested)"
        fi
    done
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
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -r, --region   AWS region (default: us-east-1)"
    echo "  -l, --list     List bucket contents after creation"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION     AWS region to use (overrides -r option)"
    echo ""
    echo "Example:"
    echo "  $0 --region us-west-2"
    echo "  AWS_REGION=eu-west-1 $0"
}

# Main function
main() {
    local list_contents=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                display_usage
                exit 0
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -l|--list)
                list_contents=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                display_usage
                exit 1
                ;;
        esac
    done
    
    echo "Setting up installers bucket..."
    echo "Bucket name: $BUCKET_NAME"
    echo "AWS region: $AWS_REGION"
    echo ""
    
    # Check prerequisites
    check_aws_cli
    check_aws_credentials
    
    # Create bucket and folder structure
    create_bucket
    create_folder_structure
    
    echo ""
    echo "Setup completed successfully!"
    echo "Bucket URL: https://s3.console.aws.amazon.com/s3/buckets/${BUCKET_NAME}"
    
    if [ "$list_contents" = true ]; then
        display_bucket_contents
    fi
}

# Run main function with all arguments
main "$@"
