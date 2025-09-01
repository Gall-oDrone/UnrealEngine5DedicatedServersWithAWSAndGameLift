#!/bin/bash

# Unreal Engine 5 Infrastructure Cleanup Script
# This script safely removes all Terraform-managed AWS resources

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
ENVIRONMENTS_DIR="$PROJECT_ROOT/environments"
MODULES_DIR="$PROJECT_ROOT/modules"
LOG_FILE="$SCRIPT_DIR/cleanup_$(date +%Y%m%d_%H%M%S).log"

# Default values
ENVIRONMENT="dev"
FORCE_CLEANUP=false
REMOVE_BACKEND=false
SKIP_CONFIRM=false
DRY_RUN=false

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [ENVIRONMENT]

Clean up Unreal Engine 5 infrastructure deployed with Terraform.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to clean up (dev, staging, prod) [default: dev]
    -f, --force             Force cleanup without confirmation prompts
    -b, --remove-backend    Also remove Terraform backend configuration
    -d, --dry-run           Show what would be destroyed without actually destroying
    -s, --skip-confirm      Skip the final confirmation prompt
    -a, --all               Clean up all environments

ENVIRONMENT:
    dev                     Development environment (default)
    staging                 Staging environment
    prod                    Production environment

EXAMPLES:
    $0                      Clean up dev environment with prompts
    $0 -e prod -f          Force cleanup of production environment
    $0 -d                  Dry run to see what would be destroyed
    $0 -a -f               Force cleanup of all environments
    $0 --remove-backend    Clean up and remove backend configuration

WARNING:
    This will permanently destroy all infrastructure resources!
    Make sure to backup any important data before proceeding.

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform >= 1.0"
        exit 1
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to validate environment
validate_environment() {
    local env="$1"
    if [[ ! -d "$ENVIRONMENTS_DIR/$env" ]]; then
        print_error "Environment '$env' does not exist"
        return 1
    fi
    return 0
}

# Function to confirm destruction
confirm_destruction() {
    local env="$1"
    
    if [[ "$FORCE_CLEANUP" == true ]] || [[ "$SKIP_CONFIRM" == true ]]; then
        return 0
    fi
    
    print_warning "════════════════════════════════════════════════════════════"
    print_warning "⚠️  WARNING: DESTRUCTIVE OPERATION"
    print_warning "════════════════════════════════════════════════════════════"
    print_warning ""
    print_warning "You are about to destroy the following:"
    print_warning "  - Environment: $env"
    print_warning "  - All EC2 instances"
    print_warning "  - All VPC resources (subnets, gateways, etc.)"
    print_warning "  - All IAM roles and policies"
    print_warning "  - All EBS volumes"
    print_warning "  - All security groups"
    print_warning "  - All CloudWatch logs"
    print_warning ""
    print_warning "This action is irreversible!"
    print_warning "════════════════════════════════════════════════════════════"
    echo ""
    
    read -p "Type 'destroy-$env' to confirm: " confirmation
    
    if [[ "$confirmation" != "destroy-$env" ]]; then
        print_error "Confirmation failed. Aborting cleanup."
        return 1
    fi
    
    return 0
}

# Function to clean up Terraform resources
cleanup_terraform_resources() {
    local env="$1"
    local env_dir="$ENVIRONMENTS_DIR/$env"
    
    print_status "Cleaning up Terraform resources for environment: $env"
    
    if [[ ! -d "$env_dir" ]]; then
        print_warning "Environment directory not found: $env_dir"
        return 1
    fi
    
    cd "$env_dir"
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    if ! terraform init -input=false >> "$LOG_FILE" 2>&1; then
        print_error "Terraform initialization failed. Check log: $LOG_FILE"
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_status "Running terraform plan -destroy (dry run)..."
        terraform plan -destroy -input=false || true
        print_warning "DRY RUN: No resources were destroyed"
        return 0
    fi
    
    # Destroy resources
    print_status "Destroying Terraform resources..."
    if terraform destroy -auto-approve -input=false >> "$LOG_FILE" 2>&1; then
        print_success "Terraform resources destroyed successfully"
    else
        print_error "Some resources may not have been destroyed. Check log: $LOG_FILE"
        return 1
    fi
    
    return 0
}

# Function to clean up local Terraform files
cleanup_local_files() {
    local env="$1"
    local env_dir="$ENVIRONMENTS_DIR/$env"
    
    print_status "Cleaning up local Terraform files for environment: $env"
    
    if [[ ! -d "$env_dir" ]]; then
        print_warning "Environment directory not found: $env_dir"
        return 0
    fi
    
    cd "$env_dir"
    
    # Remove Terraform state files
    print_status "Removing Terraform state files..."
    rm -rf .terraform* terraform.tfstate* .terraform.lock.hcl tfplan 2>/dev/null || true
    
    # Remove log files
    print_status "Removing log files..."
    rm -f *.log 2>/dev/null || true
    
    print_success "Local files cleaned up"
}

# Function to clean up AWS resources not managed by Terraform
cleanup_aws_resources() {
    local env="$1"
    
    print_status "Checking for orphaned AWS resources..."
    
    # Check for orphaned EBS volumes
    local orphaned_volumes=$(aws ec2 describe-volumes \
        --filters "Name=status,Values=available" \
        "Name=tag:Environment,Values=$env" \
        --query "Volumes[].VolumeId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$orphaned_volumes" ]]; then
        print_warning "Found orphaned EBS volumes: $orphaned_volumes"
        if [[ "$DRY_RUN" != true ]]; then
            for volume in $orphaned_volumes; do
                print_status "Deleting volume: $volume"
                aws ec2 delete-volume --volume-id "$volume" 2>/dev/null || true
            done
        fi
    fi
    
    # Check for orphaned snapshots
    local orphaned_snapshots=$(aws ec2 describe-snapshots \
        --owner-ids self \
        --filters "Name=tag:Environment,Values=$env" \
        --query "Snapshots[].SnapshotId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$orphaned_snapshots" ]]; then
        print_warning "Found orphaned snapshots: $orphaned_snapshots"
        if [[ "$DRY_RUN" != true ]]; then
            for snapshot in $orphaned_snapshots; do
                print_status "Deleting snapshot: $snapshot"
                aws ec2 delete-snapshot --snapshot-id "$snapshot" 2>/dev/null || true
            done
        fi
    fi
    
    # Check for orphaned key pairs
    local key_pairs=$(aws ec2 describe-key-pairs \
        --filters "Name=tag:Environment,Values=$env" \
        --query "KeyPairs[].KeyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$key_pairs" ]]; then
        print_warning "Found key pairs: $key_pairs"
        if [[ "$DRY_RUN" != true ]]; then
            for key in $key_pairs; do
                print_status "Deleting key pair: $key"
                aws ec2 delete-key-pair --key-name "$key" 2>/dev/null || true
            done
        fi
    fi
    
    print_success "AWS resource cleanup completed"
}

# Function to clean up CloudWatch logs
cleanup_cloudwatch_logs() {
    local env="$1"
    
    print_status "Cleaning up CloudWatch log groups..."
    
    local log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/ec2/ue5-$env" \
        --query "logGroups[].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$log_groups" ]]; then
        if [[ "$DRY_RUN" != true ]]; then
            for log_group in $log_groups; do
                print_status "Deleting log group: $log_group"
                aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
            done
        else
            print_warning "Would delete log groups: $log_groups"
        fi
    fi
    
    print_success "CloudWatch logs cleanup completed"
}

# Function to remove Terraform backend
remove_backend() {
    if [[ "$REMOVE_BACKEND" != true ]]; then
        return 0
    fi
    
    print_warning "Removing Terraform backend configuration..."
    
    # Read backend configuration if it exists
    if [[ -f "$TERRAFORM_DIR/backend.tf" ]]; then
        print_status "Found backend configuration"
        # Parse S3 backend bucket name
        local bucket=$(grep -E '^\s*bucket\s*=' "$TERRAFORM_DIR/backend.tf" | sed 's/.*=\s*"\(.*\)"/\1/' || echo "")
        
        if [[ -n "$bucket" ]]; then
            print_warning "Found S3 backend bucket: $bucket"
            if confirm_backend_removal "$bucket"; then
                if [[ "$DRY_RUN" != true ]]; then
                    print_status "Removing S3 backend bucket: $bucket"
                    aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
                    aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
                    rm -f "$TERRAFORM_DIR/backend.tf" 2>/dev/null || true
                else
                    print_warning "Would remove S3 bucket: $bucket"
                fi
            fi
        fi
    fi
    
    print_success "Backend cleanup completed"
}

# Function to confirm backend removal
confirm_backend_removal() {
    local bucket="$1"
    
    if [[ "$FORCE_CLEANUP" == true ]]; then
        return 0
    fi
    
    print_warning "This will remove the S3 backend bucket: $bucket"
    read -p "Are you sure? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        print_warning "Skipping backend removal"
        return 1
    fi
    
    return 0
}

# Function to generate cleanup report
generate_cleanup_report() {
    local env="$1"
    local report_file="$SCRIPT_DIR/cleanup_report_${env}_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
================================================================================
Terraform Infrastructure Cleanup Report
================================================================================
Date: $(date)
Environment: $env
Dry Run: $DRY_RUN
Force Mode: $FORCE_CLEANUP

Resources Cleaned:
- Terraform managed resources: ✓
- Local Terraform files: ✓
- Orphaned AWS resources: ✓
- CloudWatch logs: ✓
- Backend configuration: $(if [[ "$REMOVE_BACKEND" == true ]]; then echo "✓"; else echo "✗"; fi)

Log File: $LOG_FILE
================================================================================
EOF
    
    print_success "Cleanup report generated: $report_file"
}

# Function to clean all environments
cleanup_all_environments() {
    print_warning "Cleaning up ALL environments..."
    
    local environments=(dev staging prod)
    local failed_envs=()
    
    for env in "${environments[@]}"; do
        if validate_environment "$env"; then
            print_status "Processing environment: $env"
            if cleanup_environment "$env"; then
                print_success "Environment $env cleaned successfully"
            else
                print_error "Failed to clean environment: $env"
                failed_envs+=("$env")
            fi
        else
            print_warning "Skipping non-existent environment: $env"
        fi
    done
    
    if [[ ${#failed_envs[@]} -gt 0 ]]; then
        print_error "Failed to clean environments: ${failed_envs[*]}"
        return 1
    fi
    
    return 0
}

# Function to clean a single environment
cleanup_environment() {
    local env="$1"
    
    if ! confirm_destruction "$env"; then
        return 1
    fi
    
    # Run cleanup steps
    cleanup_terraform_resources "$env"
    cleanup_aws_resources "$env"
    cleanup_cloudwatch_logs "$env"
    cleanup_local_files "$env"
    generate_cleanup_report "$env"
    
    return 0
}

# Main execution function
main() {
    print_status "Starting Unreal Engine 5 infrastructure cleanup"
    print_status "Log file: $LOG_FILE"
    
    # Check prerequisites
    check_prerequisites
    
    # Check if cleaning all environments
    if [[ "$ENVIRONMENT" == "all" ]]; then
        cleanup_all_environments
    else
        # Validate environment
        if ! validate_environment "$ENVIRONMENT"; then
            print_error "Invalid environment: $ENVIRONMENT"
            exit 1
        fi
        
        # Clean single environment
        cleanup_environment "$ENVIRONMENT"
    fi
    
    # Remove backend if requested
    remove_backend
    
    print_success "════════════════════════════════════════════════════════════"
    print_success "Cleanup completed successfully!"
    print_success "════════════════════════════════════════════════════════════"
    print_status "Check the log file for details: $LOG_FILE"
}

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
        -f|--force)
            FORCE_CLEANUP=true
            shift
            ;;
        -b|--remove-backend)
            REMOVE_BACKEND=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--skip-confirm)
            SKIP_CONFIRM=true
            shift
            ;;
        -a|--all)
            ENVIRONMENT="all"
            shift
            ;;
        *)
            ENVIRONMENT="$1"
            shift
            ;;
    esac
done

# Run main function
main "$@"