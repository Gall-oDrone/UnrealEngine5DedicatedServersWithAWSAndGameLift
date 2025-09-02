#!/bin/bash

# Simplified Staged Deployment Script
# This script deploys the infrastructure in stages without complex monitoring

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
AUTO_APPROVE=false

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

Deploy Unreal Engine 5 infrastructure in stages.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to deploy (dev, staging, prod) [default: dev]
    -a, --auto-approve      Auto-approve Terraform changes
    -d, --destroy           Destroy the infrastructure
    -p, --password          Retrieve Windows Administrator password only

EXAMPLES:
    $0                      Deploy dev environment with prompts
    $0 -a                   Deploy with auto-approval
    $0 -d                   Destroy infrastructure
    $0 -p                   Get admin password only

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

# Function to wait for EC2 instance to be ready
wait_for_instance() {
    local instance_id=$1
    local max_wait=${2:-600}  # Default 10 minutes
    
    local elapsed=0
    local interval=15
    
    print_info "⏳ Waiting for instance $instance_id to be ready..."
    
    while [ $elapsed -lt $max_wait ]; do
        # Check instance status
        instance_state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "unknown")
        
        status_checks=$(aws ec2 describe-instance-status \
            --instance-ids "$instance_id" \
            --query 'InstanceStatuses[0].InstanceStatus.Status' \
            --output text 2>/dev/null || echo "unknown")
        
        # Check if instance is running and status checks are available
        if [[ "$instance_state" == "running" ]]; then
            if [[ "$status_checks" == "ok" ]]; then
                print_success "Instance $instance_id is ready!"
                return 0
            elif [[ "$status_checks" == "unknown" ]]; then
                # Status checks might not be available yet, wait a bit more
                if [ $elapsed -gt 300 ]; then  # After 5 minutes, consider it ready anyway
                    print_warning "Status checks not available after 5 minutes, assuming instance is ready"
                    return 0
                fi
            elif [[ "$status_checks" == "initializing" ]]; then
                # Instance is still initializing, continue waiting
                if [ $((elapsed % 60)) -eq 0 ]; then
                    print_info "Instance is initializing, please wait... ($elapsed seconds elapsed)"
                fi
            fi
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        
        if [ $((elapsed % 60)) -eq 0 ]; then
            if [[ "$status_checks" == "unknown" ]]; then
                print_info "Instance state: $instance_state, Status checks: Not available yet ($elapsed seconds elapsed)"
            fi
        fi
    done
    
    print_warning "Timeout waiting for instance $instance_id"
    return 1
}

# Function to retrieve Windows Administrator password
get_admin_password() {
    cd "$TERRAFORM_DIR"
    
    print_info "🔑 Retrieving Windows Administrator password..."
    
    # Check if terraform is initialized
    if [[ ! -d ".terraform" ]]; then
        print_error "Terraform not initialized. Please run deployment first."
        exit 1
    fi
    
    # Get the password
    ADMIN_PASSWORD=$(terraform output -raw windows_admin_password 2>/dev/null || echo "")
    
    if [[ -n "$ADMIN_PASSWORD" ]]; then
        print_success "✅ Admin password retrieved successfully!"
        echo ""
        print_info "🔐 Windows Administrator Credentials:"
        echo "  - Username: Administrator"
        echo "  - Password: $ADMIN_PASSWORD"
        echo ""
        print_info "📱 Connection Information:"
        
        # Get instance details
        INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null || echo "N/A")
        PUBLIC_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "N/A")
        
        echo "  - Instance ID: $INSTANCE_ID"
        echo "  - Public IP: $PUBLIC_IP"
        echo "  - RDP: $PUBLIC_IP:3389"
        echo "  - DCV: https://$PUBLIC_IP:8443"
        echo ""
    else
        print_error "❌ Could not retrieve admin password"
        print_info "   This might happen if:"
        echo "     - Infrastructure hasn't been deployed yet"
        echo "     - Terraform state is corrupted"
        echo "     - Output variable is not properly configured"
        echo ""
        print_info "   Try running: terraform output windows_admin_password"
        exit 1
    fi
}

# Main deployment stages
deploy_infrastructure() {
    cd "$TERRAFORM_DIR"
    
    # Stage 1: Network Infrastructure
    print_info "📦 Stage 1: Deploying network infrastructure (VPC, Subnets, Security Groups)..."
    
    local apply_args=""
    if [[ "$AUTO_APPROVE" == true ]]; then
        apply_args="-auto-approve"
    fi
    
    terraform init -upgrade
    terraform apply -target=module.networking -target=module.security $apply_args
    
    print_success "Network infrastructure deployed"
    
    # Stage 2: Compute Infrastructure
    print_info "📦 Stage 2: Deploying compute infrastructure (EC2 instance)..."
    
    terraform apply -target=module.compute $apply_args
    
    # Get instance details
    INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null || echo "")
    PUBLIC_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
    
    if [ -z "$INSTANCE_ID" ] || [ -z "$PUBLIC_IP" ]; then
        print_error "Failed to get instance details from Terraform"
        exit 1
    fi
    
    print_success "Instance deployed: $INSTANCE_ID"
    print_success "Public IP: $PUBLIC_IP"
    
    # Stage 3: Wait for Instance
    print_info "📦 Stage 3: Waiting for instance to be ready..."
    
    # Wait for instance to be ready
    if wait_for_instance "$INSTANCE_ID"; then
        print_success "✅ Instance is ready!"
    else
        print_warning "⚠️ Instance might still be starting up"
    fi
    
    # Stage 4: Deploy Monitoring
    print_info "📦 Stage 4: Deploying monitoring infrastructure..."
    
    terraform apply $apply_args
    
    print_success "Full infrastructure deployed"
}

# Parse command line arguments
DESTROY=false
GET_PASSWORD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            TERRAFORM_DIR="$ENVIRONMENTS_DIR/$ENVIRONMENT"
            shift 2
            ;;
        -a|--auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        -d|--destroy)
            DESTROY=true
            shift
            ;;
        -p|--password)
            GET_PASSWORD=true
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
main() {
    print_info "🚀 Starting infrastructure deployment"
    print_info "Environment: $ENVIRONMENT"
    
    # Check prerequisites
    check_prerequisites
    
    if [[ "$GET_PASSWORD" == true ]]; then
        # Just retrieve password
        get_admin_password
    elif [[ "$DESTROY" == true ]]; then
        cd "$TERRAFORM_DIR"
        local destroy_args=""
        if [[ "$AUTO_APPROVE" == true ]]; then
            destroy_args="-auto-approve"
        fi
        terraform destroy $destroy_args
        print_success "Infrastructure destroyed"
    else
        # Deploy infrastructure
        deploy_infrastructure
        
        # Display connection information
        cd "$TERRAFORM_DIR"
        print_success "✅ Deployment complete!"
        
        INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null || echo "")
        PUBLIC_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
        
        print_info "═══════════════════════════════════════════════════════════════"
        print_info "Connection Information:"
        print_info "═══════════════════════════════════════════════════════════════"
        echo ""
        print_success "Instance ID: $INSTANCE_ID"
        print_success "Public IP: $PUBLIC_IP"
        echo ""
        
        # Get and display admin password
        print_info "🔑 Retrieving Windows Administrator password..."
        ADMIN_PASSWORD=$(terraform output -raw windows_admin_password 2>/dev/null || echo "PASSWORD_NOT_AVAILABLE")
        
        if [[ "$ADMIN_PASSWORD" != "PASSWORD_NOT_AVAILABLE" ]]; then
            print_success "✅ Admin password retrieved successfully!"
            echo ""
            print_info "🔐 Windows Administrator Credentials:"
            echo "  - Username: Administrator"
            echo "  - Password: $ADMIN_PASSWORD"
            echo ""
        else
            print_warning "⚠️ Could not retrieve admin password automatically"
            print_info "   You can get it manually with: terraform output windows_admin_password"
            echo ""
        fi
        
        print_info "🖥️ NICE DCV (High-performance remote desktop):"
        echo "  - URL: https://$PUBLIC_IP:8443"
        echo "  - Session: ue5-session"
        echo "  - Username: Administrator"
        echo "  - Note: Accept the self-signed certificate warning"
        echo ""
        print_info "📱 Remote Desktop (RDP) - Alternative:"
        echo "  - Address: $PUBLIC_IP:3389"
        echo "  - Username: Administrator"
        echo ""
        print_info "📝 Note: User data scripts are running in the background."
        print_info "    DCV and other services may take several minutes to be ready."
        echo ""
        print_info "═══════════════════════════════════════════════════════════════"
    fi
}

# Run main function
main "$@"
