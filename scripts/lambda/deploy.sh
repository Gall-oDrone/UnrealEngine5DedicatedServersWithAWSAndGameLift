#!/bin/bash

# Lambda and API Gateway Deployment Script
# This script deploys only the lambda functions and API gateway infrastructure

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

# Default values
ENVIRONMENT="dev"
AUTO_APPROVE=false
BUILD_ONLY=false

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

Deploy Lambda functions and API Gateway infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to deploy (dev, staging, prod) [default: dev]
    -a, --auto-approve      Auto-approve Terraform changes
    -b, --build-only        Only build Lambda functions, don't deploy
    -d, --destroy           Destroy the Lambda infrastructure
    -v, --validate-only     Only validate Terraform configuration

EXAMPLES:
    $0                      Deploy dev environment with prompts
    $0 -a                   Deploy with auto-approval
    $0 -e staging           Deploy to staging environment
    $0 -b                   Only build Lambda functions
    $0 -d                   Destroy Lambda infrastructure
    $0 -v                   Validate Terraform only

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
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to check optional tools
check_optional_tools() {
    print_info "Checking optional build tools..."
    
    # Check for Python/pip
    if command -v python3 &> /dev/null && command -v pip3 &> /dev/null; then
        print_success "✓ Python 3 and pip3 available"
    else
        print_warning "Python 3 or pip3 not found. Python Lambda builds may fail."
    fi
    
    # Check for Go
    if command -v go &> /dev/null; then
        print_success "✓ Go available"
    else
        print_warning "Go not found. Go Lambda builds may fail."
        print_warning "Install from: https://golang.org/dl/"
    fi
    
    print_success "Optional tools check completed"
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

# Function to build Lambda functions
build_lambdas() {
    print_progress "Building Lambda functions..."
    
    local module_dir="$PROJECT_ROOT/modules/lambda"
    
    # Build Python Lambda
    if [ -f "$module_dir/python/src/handler.py" ]; then
        print_info "Building Python Lambda..."
        if [ -f "$module_dir/scripts/build_python.sh" ]; then
            bash "$module_dir/scripts/build_python.sh" "$module_dir"
            print_success "✓ Python Lambda build complete"
        else
            print_warning "Python build script not found, skipping..."
        fi
    else
        print_warning "Python Lambda handler not found, skipping..."
    fi
    
    # Build Go Lambda
    if [ -f "$module_dir/go/src/main.go" ]; then
        print_info "Building Go Lambda..."
        if [ -f "$module_dir/scripts/build_go.sh" ]; then
            bash "$module_dir/scripts/build_go.sh" "$module_dir"
            print_success "✓ Go Lambda build complete"
        else
            print_warning "Go build script not found, skipping..."
        fi
    else
        print_warning "Go Lambda handler not found, skipping..."
    fi
    
    print_success "Lambda builds completed"
}

# Function to run Terraform
run_terraform() {
    local operation=$1
    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    
    cd "$env_dir"
    
    # Initialize Terraform if needed
    if [ ! -d ".terraform" ]; then
        print_info "Initializing Terraform..."
        terraform init
    fi
    
    # Run Terraform operation
    case $operation in
        "plan")
            print_info "Running Terraform plan (targeting Lambda modules only)..."
            if [ "$AUTO_APPROVE" = true ]; then
                terraform plan -target=module.lambda -out=tfplan
            else
                terraform plan -target=module.lambda
            fi
            ;;
        "apply")
            print_info "Applying Terraform (targeting Lambda modules only)..."
            if [ "$AUTO_APPROVE" = true ]; then
                terraform apply -target=module.lambda -auto-approve
            else
                terraform apply -target=module.lambda
            fi
            print_success "Lambda infrastructure deployed successfully"
            ;;
        "destroy")
            print_info "Destroying Lambda infrastructure..."
            if [ "$AUTO_APPROVE" = true ]; then
                terraform destroy -target=module.lambda -auto-approve
            else
                terraform destroy -target=module.lambda
            fi
            print_success "Lambda infrastructure destroyed"
            ;;
        "validate")
            print_info "Validating Terraform configuration..."
            terraform validate
            print_success "✓ Terraform configuration is valid"
            ;;
    esac
}

# Function to display deployment summary
display_summary() {
    print_progress "Deployment Summary"
    
    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    cd "$env_dir"
    
    # Get outputs
    if [ -f "terraform.tfstate" ] || [ -f ".terraform/terraform.tfstate" ]; then
        print_info "Lambda Deployment Outputs:"
        
        # Try to get API Gateway URL
        api_url=$(terraform output -raw api_gateway_stage_url 2>/dev/null || echo "")
        if [ -n "$api_url" ]; then
            print_success "API Gateway URL: $api_url"
        fi
        
        # Try to get Lambda function names
        python_func=$(terraform output -raw python_lambda_function_name 2>/dev/null || echo "")
        if [ -n "$python_func" ]; then
            print_success "Python Lambda: $python_func"
        fi
        
        go_func=$(terraform output -raw go_lambda_function_name 2>/dev/null || echo "")
        if [ -n "$go_func" ]; then
            print_success "Go Lambda: $go_func"
        fi
    fi
}

# Main deployment function
deploy() {
    print_progress "Starting Lambda deployment for environment: $ENVIRONMENT"
    
    # Validate environment
    validate_environment "$ENVIRONMENT"
    
    # Build Lambda functions
    build_lambdas
    
    # If build-only, exit here
    if [ "$BUILD_ONLY" = true ]; then
        print_success "Build-only mode: skipping deployment"
        exit 0
    fi
    
    # Run Terraform
    run_terraform "apply"
    
    # Display summary
    display_summary
    
    print_success "Lambda deployment completed successfully!"
}

# Parse command line arguments
DESTROY=false
VALIDATE_ONLY=false

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
        -b|--build-only)
            BUILD_ONLY=true
            shift
            ;;
        -d|--destroy)
            DESTROY=true
            shift
            ;;
        -v|--validate-only)
            VALIDATE_ONLY=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
check_prerequisites
check_optional_tools

if [ "$VALIDATE_ONLY" = true ]; then
    validate_environment "$ENVIRONMENT"
    run_terraform "validate"
    exit 0
fi

if [ "$DESTROY" = true ]; then
    validate_environment "$ENVIRONMENT"
    run_terraform "destroy"
    exit 0
fi

deploy

