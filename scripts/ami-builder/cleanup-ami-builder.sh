#!/bin/bash

# AMI Builder Cleanup Script
# This script cleans up AMI builder instances, AMIs, and related resources

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

print_info() {
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

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up AMI builder resources and artifacts.

OPTIONS:
    -h, --help              Show this help message
    -a, --all               Clean up all AMI builder resources
    -i, --instances         Clean up only AMI builder instances
    -m, --amis              Clean up only custom AMIs
    -f, --force             Force cleanup without confirmation
    -d, --dry-run           Show what would be cleaned up without doing it

EXAMPLES:
    $0                      Interactive cleanup
    $0 -a                   Clean up everything
    $0 -i                   Clean up only instances
    $0 -m                   Clean up only AMIs
    $0 -f                   Force cleanup without prompts

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    # Set AWS region
    export AWS_DEFAULT_REGION="us-east-1"
    export AWS_REGION="us-east-1"
    
    print_success "Prerequisites check passed"
}

# Function to find AMI builder instances
find_ami_builder_instances() {
    print_info "Finding AMI builder instances..."
    
    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Purpose,Values=AMI-Builder" \
        --query 'Reservations[].Instances[].{InstanceId:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name,LaunchTime:LaunchTime}' \
        --output json)
    
    echo "$instances"
}

# Function to find custom AMIs
find_custom_amis() {
    print_info "Finding custom AMIs..."
    
    local amis=$(aws ec2 describe-images \
        --owners self \
        --filters "Name=tag:Purpose,Values=UnrealEngine5-Development" \
        --query 'Images[].{ImageId:ImageId,Name:Name,Description:Description,CreationDate:CreationDate,State:State}' \
        --output json)
    
    echo "$amis"
}

# Function to display resources
display_resources() {
    local instances="$1"
    local amis="$2"
    
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "                    AMI BUILDER RESOURCES"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    
    # Display instances
    local instance_count=$(echo "$instances" | jq '. | length')
    if [[ $instance_count -gt 0 ]]; then
        echo "Instances ($instance_count):"
        echo "$instances" | jq -r '.[] | "  \(.InstanceId) - \(.Name) (\(.State)) - \(.LaunchTime)"'
        echo
    else
        echo "No AMI builder instances found."
        echo
    fi
    
    # Display AMIs
    local ami_count=$(echo "$amis" | jq '. | length')
    if [[ $ami_count -gt 0 ]]; then
        echo "Custom AMIs ($ami_count):"
        echo "$amis" | jq -r '.[] | "  \(.ImageId) - \(.Name) (\(.State)) - \(.CreationDate)"'
        echo
    else
        echo "No custom AMIs found."
        echo
    fi
}

# Function to cleanup instances
cleanup_instances() {
    local instances="$1"
    local force="$2"
    
    local instance_count=$(echo "$instances" | jq '. | length')
    if [[ $instance_count -eq 0 ]]; then
        print_info "No instances to clean up."
        return
    fi
    
    echo "Found $instance_count AMI builder instance(s):"
    echo "$instances" | jq -r '.[] | "  \(.InstanceId) - \(.Name)"'
    echo
    
    if [[ "$force" != "true" ]]; then
        read -p "Do you want to terminate these instances? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Instance cleanup cancelled."
            return
        fi
    fi
    
    print_info "Terminating instances..."
    
    local instance_ids=$(echo "$instances" | jq -r '.[].InstanceId')
    for instance_id in $instance_ids; do
        print_info "Terminating instance: $instance_id"
        aws ec2 terminate-instances --instance-ids "$instance_id"
    done
    
    print_success "All instances terminated successfully."
}

# Function to cleanup AMIs
cleanup_amis() {
    local amis="$1"
    local force="$2"
    
    local ami_count=$(echo "$amis" | jq '. | length')
    if [[ $ami_count -eq 0 ]]; then
        print_info "No AMIs to clean up."
        return
    fi
    
    echo "Found $ami_count custom AMI(s):"
    echo "$amis" | jq -r '.[] | "  \(.ImageId) - \(.Name)"'
    echo
    
    if [[ "$force" != "true" ]]; then
        read -p "Do you want to deregister these AMIs? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "AMI cleanup cancelled."
            return
        fi
    fi
    
    print_info "Deregistering AMIs..."
    
    local ami_ids=$(echo "$amis" | jq -r '.[].ImageId')
    for ami_id in $ami_ids; do
        print_info "Deregistering AMI: $ami_id"
        aws ec2 deregister-image --image-id "$ami_id"
    done
    
    print_success "All AMIs deregistered successfully."
}

# Function to cleanup temporary files
cleanup_temp_files() {
    print_info "Cleaning up temporary files..."
    
    local temp_files=(
        "/tmp/ami_builder_instance_id"
        "/tmp/ami_builder_instance_name"
        "/tmp/ami_builder_ami_id"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            print_info "Removed: $file"
        fi
    done
    
    print_success "Temporary files cleaned up."
}

# Function to main cleanup
main_cleanup() {
    local instances=$(find_ami_builder_instances)
    local amis=$(find_custom_amis)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN MODE - No changes will be made"
        display_resources "$instances" "$amis"
        return
    fi
    
    display_resources "$instances" "$amis"
    
    if [[ "$CLEANUP_INSTANCES" == "true" || "$CLEANUP_ALL" == "true" ]]; then
        cleanup_instances "$instances" "$FORCE"
    fi
    
    if [[ "$CLEANUP_AMIS" == "true" || "$CLEANUP_ALL" == "true" ]]; then
        cleanup_amis "$amis" "$FORCE"
    fi
    
    cleanup_temp_files
    
    print_success "Cleanup completed successfully!"
}

# Parse command line arguments
CLEANUP_ALL=false
CLEANUP_INSTANCES=false
CLEANUP_AMIS=false
FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -a|--all)
            CLEANUP_ALL=true
            shift
            ;;
        -i|--instances)
            CLEANUP_INSTANCES=true
            shift
            ;;
        -m|--amis)
            CLEANUP_AMIS=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# If no specific cleanup type specified, default to all
if [[ "$CLEANUP_ALL" == "false" && "$CLEANUP_INSTANCES" == "false" && "$CLEANUP_AMIS" == "false" ]]; then
    CLEANUP_ALL=true
fi

# Main execution
main() {
    print_info "Starting AMI Builder cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Run cleanup
    main_cleanup
}

# Run main function
main
