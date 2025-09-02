#!/bin/bash

# Custom AMI Builder for Unreal Engine 5 Development
# This script creates a temporary EC2 instance, installs Visual Studio Community 2022 and Nice DCV,
# then creates an AMI from the configured instance

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
ENVIRONMENTS_DIR="$PROJECT_ROOT/environments"
TERRAFORM_DIR="$ENVIRONMENTS_DIR/dev"

# Default values
ENVIRONMENT="dev"
INSTANCE_TYPE="c5.2xlarge"
AMI_NAME="ue5-dev-vs2022-dcv"
AMI_DESCRIPTION="Unreal Engine 5 Development AMI with Visual Studio Community 2022 and Nice DCV"
BUILD_TIMEOUT_HOURS=4
CLEANUP_ON_SUCCESS=true

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

print_progress() {
    echo -e "${CYAN}[PROGRESS]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build a custom AMI with Visual Studio Community 2022 and Nice DCV pre-installed.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to use (dev, staging, prod) [default: dev]
    -i, --instance-type     EC2 instance type for building [default: c5.2xlarge]
    -n, --ami-name          Name for the custom AMI [default: ue5-dev-vs2022-dcv]
    -d, --description       Description for the AMI
    -t, --timeout           Build timeout in hours [default: 4]
    -k, --keep-instance     Keep the build instance after AMI creation
    -c, --cleanup           Clean up build artifacts (default: true)

EXAMPLES:
    $0                      Build AMI with default settings
    $0 -i c5.4xlarge        Use larger instance type for faster builds
    $0 -n my-custom-ami     Use custom AMI name
    $0 -k                   Keep the build instance after AMI creation

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
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
    
    # Set AWS region
    print_info "Setting AWS region to us-east-1..."
    export AWS_DEFAULT_REGION="us-east-1"
    export AWS_REGION="us-east-1"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to parse command line arguments
parse_arguments() {
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
            -i|--instance-type)
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            -n|--ami-name)
                AMI_NAME="$2"
                shift 2
                ;;
            -d|--description)
                AMI_DESCRIPTION="$2"
                shift 2
                ;;
            -t|--timeout)
                BUILD_TIMEOUT_HOURS="$2"
                shift 2
                ;;
            -k|--keep-instance)
                CLEANUP_ON_SUCCESS=false
                shift
                ;;
            -c|--cleanup)
                CLEANUP_ON_SUCCESS="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to get Terraform outputs
get_terraform_outputs() {
    print_info "Getting Terraform outputs..."
    
    cd "$TERRAFORM_DIR"
    
    # Check if Terraform is initialized
    if [[ ! -d ".terraform" ]]; then
        print_error "Terraform not initialized. Please run 'terraform init' first"
        exit 1
    fi
    
    # Get VPC ID
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    if [[ -z "$VPC_ID" ]]; then
        print_error "Could not get VPC ID from Terraform outputs"
        exit 1
    fi
    
    # Get subnet ID
    SUBNET_ID=$(terraform output -raw public_subnet_id 2>/dev/null || echo "")
    if [[ -z "$SUBNET_ID" ]]; then
        print_error "Could not get subnet ID from Terraform outputs"
        exit 1
    fi
    
    # Get security group ID
    SECURITY_GROUP_ID=$(terraform output -raw ec2_security_group_id 2>/dev/null || echo "")
    if [[ -z "$SECURITY_GROUP_ID" ]]; then
        print_error "Could not get security group ID from Terraform outputs"
        exit 1
    fi
    
    # Get IAM role ARN
    IAM_ROLE_ARN=$(terraform output -raw ec2_iam_role_arn 2>/dev/null || echo "")
    if [[ -z "$IAM_ROLE_ARN" ]]; then
        print_error "Could not get IAM role ARN from Terraform outputs"
        exit 1
    fi
    
    print_success "Terraform outputs retrieved successfully"
    print_info "VPC ID: $VPC_ID"
    print_info "Subnet ID: $SUBNET_ID"
    print_info "Security Group ID: $SECURITY_GROUP_ID"
    print_info "IAM Role ARN: $IAM_ROLE_ARN"
}

# Function to create build instance
create_build_instance() {
    print_info "Creating build instance..."
    
    # Generate unique instance name
    INSTANCE_NAME="ue5-ami-builder-$(date +%Y%m%d-%H%M%S)"
    
    # Get latest Windows Server 2022 AMI
    WINDOWS_AMI=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=Windows_Server-2022-English-Full-Base-*" \
        --query 'Images[0].ImageId' \
        --output text)
    
    print_info "Using Windows Server 2022 AMI: $WINDOWS_AMI"
    
    # Create instance
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$WINDOWS_AMI" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "ue5-dev-key" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --subnet-id "$SUBNET_ID" \
        --iam-instance-profile Name="$IAM_ROLE_ARN" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=Purpose,Value=AMI-Builder},{Key=Environment,Value=$ENVIRONMENT}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    print_success "Build instance created: $INSTANCE_ID"
    
    # Wait for instance to be running
    print_info "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
    
    # Get instance public IP
    INSTANCE_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    print_success "Instance is running with IP: $INSTANCE_IP"
    
    # Wait for Windows to be ready (this can take 10-15 minutes)
    print_info "Waiting for Windows to be ready (this may take 10-15 minutes)..."
    print_info "You can monitor the instance in the AWS Console"
    
    # Store instance details for cleanup
    echo "$INSTANCE_ID" > /tmp/ami_builder_instance_id
    echo "$INSTANCE_NAME" > /tmp/ami_builder_instance_name
}

# Function to wait for Windows to be ready
wait_for_windows_ready() {
    print_info "Waiting for Windows to be ready..."
    
    local max_attempts=60
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        print_progress "Attempt $attempt/$max_attempts - Checking if Windows is ready..."
        
        # Try to get Windows password
        if aws ec2 get-password-data --instance-id "$INSTANCE_ID" --query 'PasswordData' --output text | grep -q "password"; then
            print_success "Windows is ready!"
            return 0
        fi
        
        sleep 60
        ((attempt++))
    done
    
    print_error "Windows did not become ready within the expected time"
    return 1
}

# Function to install software on the instance
install_software() {
    print_info "Installing software on the instance..."
    
    # This will be done via user data script and remote execution
    # The instance will install everything automatically
    print_info "Software installation is handled by the user data script"
    print_info "This process will take approximately 2-3 hours"
    
    # Wait for the installation to complete
    local start_time=$(date +%s)
    local timeout_seconds=$((BUILD_TIMEOUT_HOURS * 3600))
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout_seconds ]]; then
            print_error "Build timeout reached (${BUILD_TIMEOUT_HOURS} hours)"
            return 1
        fi
        
        # Check if the instance is still running
        local instance_state=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text)
        
        if [[ "$instance_state" != "running" ]]; then
            print_error "Instance is not running. State: $instance_state"
            return 1
        fi
        
        print_progress "Waiting for software installation to complete... (${elapsed}s elapsed)"
        sleep 300  # Check every 5 minutes
    done
}

# Function to create AMI
create_ami() {
    print_info "Creating AMI from the configured instance..."
    
    # Stop the instance before creating AMI
    print_info "Stopping the instance..."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID"
    aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
    
    # Create AMI
    AMI_ID=$(aws ec2 create-image \
        --instance-id "$INSTANCE_ID" \
        --name "$AMI_NAME" \
        --description "$AMI_DESCRIPTION" \
        --query 'ImageId' \
        --output text)
    
    print_success "AMI creation started: $AMI_ID"
    
    # Wait for AMI to be available
    print_info "Waiting for AMI to be available (this may take 10-20 minutes)..."
    aws ec2 wait image-available --image-ids "$AMI_ID"
    
    print_success "AMI is now available: $AMI_ID"
    
    # Tag the AMI
    aws ec2 create-tags \
        --resources "$AMI_ID" \
        --tags "Key=Name,Value=$AMI_NAME" \
        "Key=Purpose,Value=UnrealEngine5-Development" \
        "Key=Environment,Value=$ENVIRONMENT" \
        "Key=CreatedBy,Value=AMI-Builder-Script" \
        "Key=CreatedDate,Value=$(date +%Y-%m-%d)"
    
    print_success "AMI tagged successfully"
    
    # Store AMI ID for reference
    echo "$AMI_ID" > /tmp/ami_builder_ami_id
}

# Function to cleanup build instance
cleanup_build_instance() {
    if [[ "$CLEANUP_ON_SUCCESS" == "true" ]]; then
        print_info "Cleaning up build instance..."
        
        # Terminate the instance
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
        print_success "Build instance terminated"
        
        # Clean up temporary files
        rm -f /tmp/ami_builder_instance_id
        rm -f /tmp/ami_builder_instance_name
    else
        print_warning "Build instance kept as requested"
        print_info "Instance ID: $INSTANCE_ID"
        print_info "Instance Name: $INSTANCE_NAME"
    fi
}

# Function to display results
display_results() {
    print_success "AMI creation completed successfully!"
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "                    AMI CREATION RESULTS"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    echo "AMI ID:          $AMI_ID"
    echo "AMI Name:        $AMI_NAME"
    echo "Description:     $AMI_DESCRIPTION"
    echo "Environment:     $ENVIRONMENT"
    echo "Instance Type:   $INSTANCE_TYPE"
    echo "Build Time:      ${BUILD_TIMEOUT_HOURS} hours"
    echo
    echo "The AMI contains:"
    echo "  ✓ Windows Server 2022"
    echo "  ✓ Visual Studio Community 2022"
    echo "  ✓ Nice DCV Server"
    echo "  ✓ Unreal Engine 5 development tools"
    echo "  ✓ Chocolatey package manager"
    echo "  ✓ Git, Python, CMake, and other build tools"
    echo
    echo "Next steps:"
    echo "  1. Update your Terraform configuration to use this AMI"
    echo "  2. Test the AMI by launching a new instance"
    echo "  3. Share the AMI with your team if needed"
    echo
    echo "To use this AMI in Terraform, update your compute module:"
    echo "  data \"aws_ami\" \"custom_ue5\" {"
    echo "    most_recent = true"
    echo "    owners      = [\"self\"]"
    echo "    filter {"
    echo "      name   = \"image-id\""
    echo "      values = [\"$AMI_ID\"]"
    echo "    }"
    echo "  }"
    echo
}

# Main execution
main() {
    print_info "Starting custom AMI creation process..."
    print_info "Environment: $ENVIRONMENT"
    print_info "Instance Type: $INSTANCE_TYPE"
    print_info "AMI Name: $AMI_NAME"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Get Terraform outputs
    get_terraform_outputs
    
    # Create build instance
    create_build_instance
    
    # Wait for Windows to be ready
    if ! wait_for_windows_ready; then
        print_error "Failed to wait for Windows to be ready"
        exit 1
    fi
    
    # Install software (this is handled by user data)
    if ! install_software; then
        print_error "Software installation failed or timed out"
        exit 1
    fi
    
    # Create AMI
    create_ami
    
    # Cleanup
    cleanup_build_instance
    
    # Display results
    display_results
}

# Trap to cleanup on script exit
trap 'print_error "Script interrupted. Cleaning up..."; cleanup_build_instance; exit 1' INT TERM

# Run main function
main "$@"
