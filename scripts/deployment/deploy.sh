#!/bin/bash

# Unreal Engine 5 Infrastructure Deployment Script
# This script deploys the infrastructure using Terraform with proper error handling

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
ENVIRONMENTS_DIR="$PROJECT_ROOT/environments"

# Default values
ENVIRONMENT="dev"
AUTO_APPROVE=false
PLAN_ONLY=false
DESTROY=false
BACKEND_CONFIG=""

# Function to print colored output
print_status() {
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
Usage: $0 [OPTIONS] [ENVIRONMENT]

Deploy Unreal Engine 5 infrastructure using Terraform.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to deploy (dev, staging, prod) [default: dev]
    -a, --auto-approve      Auto-approve Terraform changes
    -p, --plan-only         Only run terraform plan, don't apply
    -d, --destroy           Destroy the infrastructure
    -b, --backend-config    Backend configuration file
    -v, --validate          Validate Terraform configuration

ENVIRONMENT:
    dev                     Development environment (default)
    staging                 Staging environment
    prod                    Production environment

EXAMPLES:
    $0                      Deploy dev environment
    $0 -e prod -a          Deploy production environment with auto-approve
    $0 -e staging -p       Plan staging environment changes
    $0 -e dev -d           Destroy dev environment
    $0 -v                  Validate Terraform configuration

EOF
}

# Function to validate environment
validate_environment() {
    local env="$1"
    if [[ ! -d "$ENVIRONMENTS_DIR/$env" ]]; then
        print_error "Environment '$env' does not exist. Available environments:"
        ls -1 "$ENVIRONMENTS_DIR" 2>/dev/null || print_error "No environments found"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform >= 1.0"
        exit 1
    fi
    
    # Check Terraform version
    local tf_version=$(terraform version -json | jq -r '.terraform_version')
    local required_version="1.0.0"
    
    if [[ "$(printf '%s\n' "$required_version" "$tf_version" | sort -V | head -n1)" != "$required_version" ]]; then
        print_error "Terraform version $tf_version is older than required version $required_version"
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

# Function to validate Terraform configuration
validate_terraform() {
    print_status "Validating Terraform configuration..."
    
    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    cd "$env_dir"
    
    if ! terraform validate; then
        print_error "Terraform validation failed"
        exit 1
    fi
    
    print_success "Terraform validation passed"
}

# Function to initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."
    
    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    cd "$env_dir"
    
    local init_args=""
    if [[ -n "$BACKEND_CONFIG" ]]; then
        init_args="-backend-config=$BACKEND_CONFIG"
    fi
    
    if ! terraform init $init_args; then
        print_error "Terraform initialization failed"
        exit 1
    fi
    
    print_success "Terraform initialized successfully"
}

# Function to plan Terraform changes
plan_terraform() {
    print_status "Planning Terraform changes..."
    
    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    cd "$env_dir"
    
    if ! terraform plan -out=tfplan; then
        print_error "Terraform plan failed"
        exit 1
    fi
    
    print_success "Terraform plan completed successfully"
}

# Function to apply Terraform changes
apply_terraform() {
    print_status "Applying Terraform changes..."
    
    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    cd "$env_dir"
    
    local apply_args=""
    if [[ "$AUTO_APPROVE" == true ]]; then
        apply_args="-auto-approve"
    fi
    
    if [[ "$DESTROY" == true ]]; then
        if ! terraform destroy $apply_args; then
            print_error "Terraform destroy failed"
            exit 1
        fi
        print_success "Infrastructure destroyed successfully"
    else
        if ! terraform apply $apply_args tfplan; then
            print_error "Terraform apply failed"
            exit 1
        fi
        print_success "Infrastructure deployed successfully"
    fi
}

# Function to show outputs
show_outputs() {
    if [[ "$DESTROY" == true ]] || [[ "$PLAN_ONLY" == true ]]; then
        return
    fi
    
    print_status "Retrieving deployment outputs..."
    
    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    cd "$env_dir"
    
    terraform output
}

# Function to show deployment summary
show_deployment_summary() {
    if [[ "$DESTROY" == true ]] || [[ "$PLAN_ONLY" == true ]]; then
        return
    fi
    
    print_status "Deployment Summary:"
    echo "===================="
    echo "Environment: $ENVIRONMENT"
    echo "Region: $(terraform output -raw aws_region 2>/dev/null || echo 'N/A')"
    echo "Instance IP: $(terraform output -raw instance_public_ip 2>/dev/null || echo 'N/A')"
    echo "Dashboard URL: $(terraform output -raw dashboard_url 2>/dev/null || echo 'N/A')"
    echo ""
    print_warning "Remember to:"
    echo "1. Update security groups with your IP address"
    echo "2. Configure RDP access if needed"
    echo "3. Monitor costs in AWS Console"
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
        -a|--auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        -p|--plan-only)
            PLAN_ONLY=true
            shift
            ;;
        -d|--destroy)
            DESTROY=true
            shift
            ;;
        -b|--backend-config)
            BACKEND_CONFIG="$2"
            shift 2
            ;;
        -v|--validate)
            validate_environment "$ENVIRONMENT"
            check_prerequisites
            init_terraform
            validate_terraform
            exit 0
            ;;
        *)
            ENVIRONMENT="$1"
            shift
            ;;
    esac
done

# Main execution
main() {
    print_status "Starting Unreal Engine 5 infrastructure deployment"
    print_status "Environment: $ENVIRONMENT"
    print_status "Project root: $PROJECT_ROOT"
    
    # Validate environment
    validate_environment "$ENVIRONMENT"
    
    # Check prerequisites
    check_prerequisites
    
    # Initialize Terraform first (required before validation)
    init_terraform
    
    # Validate Terraform configuration
    validate_terraform
    
    if [[ "$PLAN_ONLY" == true ]]; then
        plan_terraform
        print_success "Plan completed. Review the plan above."
        exit 0
    fi
    
    # Plan and apply
    plan_terraform
    apply_terraform
    
    # Show outputs and summary
    show_outputs
    show_deployment_summary
    
    print_success "Deployment completed successfully!"
}

# Run main function
main "$@" 