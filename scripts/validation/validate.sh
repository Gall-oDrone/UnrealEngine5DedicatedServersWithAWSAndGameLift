#!/bin/bash

# Unreal Engine 5 Infrastructure Validation Script
# This script validates the Terraform configuration and infrastructure

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
VERBOSE=false
CHECK_SECURITY=true
CHECK_COST=true

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

Validate Unreal Engine 5 infrastructure configuration and deployment.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to validate (dev, staging, prod) [default: dev]
    -v, --verbose           Enable verbose output
    --no-security           Skip security checks
    --no-cost               Skip cost analysis

ENVIRONMENT:
    dev                     Development environment (default)
    staging                 Staging environment
    prod                    Production environment

EXAMPLES:
    $0                      Validate dev environment
    $0 -e prod -v          Validate production environment with verbose output
    $0 --no-security       Skip security checks
    $0 --no-cost           Skip cost analysis

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
    
    local missing_tools=()
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_error "Please install the missing tools and try again"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to validate Terraform configuration
validate_terraform_config() {
    print_status "Validating Terraform configuration..."
    
    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    cd "$env_dir"
    
    # Check if terraform.tfvars exists
    if [[ ! -f "terraform.tfvars" ]]; then
        print_warning "terraform.tfvars not found. Using default values."
    fi
    
    # Validate Terraform configuration
    if ! terraform validate; then
        print_error "Terraform validation failed"
        exit 1
    fi
    
    # Format check
    if ! terraform fmt -check -recursive; then
        print_warning "Terraform files are not properly formatted"
        if [[ "$VERBOSE" == true ]]; then
            print_status "Run 'terraform fmt -recursive' to format files"
        fi
    fi
    
    print_success "Terraform configuration validation passed"
}

# Function to check security configuration
check_security() {
    if [[ "$CHECK_SECURITY" != true ]]; then
        return
    fi
    
    print_status "Checking security configuration..."
    
    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    cd "$env_dir"
    
    local security_issues=()
    
    # Check allowed CIDR blocks
    local allowed_cidrs=$(terraform output -json allowed_cidr_blocks 2>/dev/null | jq -r '.[]' || echo "")
    if [[ -n "$allowed_cidrs" ]]; then
        while IFS= read -r cidr; do
            if [[ "$cidr" == "0.0.0.0/0" ]]; then
                security_issues+=("WARNING: Allowing access from anywhere (0.0.0.0/0)")
            fi
        done <<< "$allowed_cidrs"
    fi
    
    # Check if KMS is enabled
    local kms_enabled=$(terraform output -json enable_kms 2>/dev/null | jq -r '.' || echo "false")
    if [[ "$kms_enabled" != "true" ]]; then
        security_issues+=("INFO: KMS encryption not enabled")
    fi
    
    # Check if VPC Flow Logs are enabled
    local flow_logs_enabled=$(terraform output -json enable_vpc_flow_logs 2>/dev/null | jq -r '.' || echo "false")
    if [[ "$flow_logs_enabled" != "true" ]]; then
        security_issues+=("INFO: VPC Flow Logs not enabled")
    fi
    
    # Report security issues
    if [[ ${#security_issues[@]} -gt 0 ]]; then
        print_warning "Security considerations:"
        for issue in "${security_issues[@]}"; do
            echo "  - $issue"
        done
    else
        print_success "Security configuration looks good"
    fi
}

# Function to analyze costs
analyze_costs() {
    if [[ "$CHECK_COST" != true ]]; then
        return
    fi
    
    print_status "Analyzing estimated costs..."
    
    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    cd "$env_dir"
    
    # Get instance type
    local instance_type=$(terraform output -json instance_type 2>/dev/null | jq -r '.' || echo "c5.2xlarge")
    
    # Get volume sizes
    local root_volume_size=$(terraform output -json root_volume_size 2>/dev/null | jq -r '.' || echo "100")
    local data_volume_size=$(terraform output -json data_volume_size 2>/dev/null | jq -r '.' || echo "500")
    
    # Get NAT Gateway setting
    local nat_enabled=$(terraform output -json enable_nat_gateway 2>/dev/null | jq -r '.' || echo "false")
    
    echo "Cost Analysis:"
    echo "=============="
    echo "Instance Type: $instance_type"
    echo "Root Volume: ${root_volume_size}GB"
    echo "Data Volume: ${data_volume_size}GB"
    echo "NAT Gateway: $nat_enabled"
    echo ""
    
    # Rough cost estimates (these are approximate)
    local instance_cost=0
    case $instance_type in
        "c5.2xlarge")
            instance_cost=300
            ;;
        "c5.4xlarge")
            instance_cost=600
            ;;
        "c5.9xlarge")
            instance_cost=1350
            ;;
        *)
            instance_cost=400
            ;;
    esac
    
    local volume_cost=$(( (root_volume_size + data_volume_size) * 8 / 100 ))
    local nat_cost=0
    if [[ "$nat_enabled" == "true" ]]; then
        nat_cost=45
    fi
    
    local total_cost=$((instance_cost + volume_cost + nat_cost + 20))  # +20 for other services
    
    echo "Estimated Monthly Costs:"
    echo "  EC2 Instance: ~\$${instance_cost}"
    echo "  EBS Volumes: ~\$${volume_cost}"
    echo "  NAT Gateway: ~\$${nat_cost}"
    echo "  Other Services: ~\$20"
    echo "  Total: ~\$${total_cost}"
    echo ""
    
    print_warning "These are rough estimates. Actual costs may vary based on usage."
}

# Function to check module structure
check_module_structure() {
    print_status "Checking module structure..."
    
    local modules_dir="$PROJECT_ROOT/modules"
    local missing_modules=()
    
    # Check if all required modules exist
    local required_modules=("networking" "compute" "security" "monitoring")
    for module in "${required_modules[@]}"; do
        if [[ ! -d "$modules_dir/$module" ]]; then
            missing_modules+=("$module")
        fi
    done
    
    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        print_error "Missing modules: ${missing_modules[*]}"
        exit 1
    fi
    
    # Check if modules have required files
    for module in "${required_modules[@]}"; do
        local module_dir="$modules_dir/$module"
        local required_files=("main.tf" "variables.tf" "outputs.tf")
        
        for file in "${required_files[@]}"; do
            if [[ ! -f "$module_dir/$file" ]]; then
                print_warning "Module $module missing $file"
            fi
        done
    done
    
    print_success "Module structure validation passed"
}

# Function to check documentation
check_documentation() {
    print_status "Checking documentation..."
    
    local docs_dir="$PROJECT_ROOT/docs"
    local missing_docs=()
    
    # Check for required documentation
    local required_docs=("README.md" "architecture/README.md" "deployment-guides/README.md")
    for doc in "${required_docs[@]}"; do
        if [[ ! -f "$docs_dir/$doc" ]]; then
            missing_docs+=("$doc")
        fi
    done
    
    if [[ ${#missing_docs[@]} -gt 0 ]]; then
        print_warning "Missing documentation: ${missing_docs[*]}"
    else
        print_success "Documentation check passed"
    fi
}

# Function to run comprehensive validation
run_validation() {
    print_status "Running comprehensive validation for environment: $ENVIRONMENT"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Validate environment
    validate_environment "$ENVIRONMENT"
    
    # Check module structure
    check_module_structure
    
    # Check documentation
    check_documentation
    
    # Validate Terraform configuration
    validate_terraform_config
    
    # Check security (if enabled)
    check_security
    
    # Analyze costs (if enabled)
    analyze_costs
    
    echo ""
    print_success "Validation completed successfully!"
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
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --no-security)
            CHECK_SECURITY=false
            shift
            ;;
        --no-cost)
            CHECK_COST=false
            shift
            ;;
        *)
            ENVIRONMENT="$1"
            shift
            ;;
    esac
done

# Run validation
run_validation 