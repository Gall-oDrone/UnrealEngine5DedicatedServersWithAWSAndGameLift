#!/bin/bash

# Quick Fix Script for DCV Port 8443
# This script immediately adds the missing DCV port to the security group

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
ENVIRONMENTS_DIR="$PROJECT_ROOT/environments"
TERRAFORM_DIR="$ENVIRONMENTS_DIR/dev"

# Default values
ENVIRONMENT="dev"
AUTO_APPROVE=false

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Quick fix for DCV port 8443 connectivity issue.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to fix (dev, staging, prod) [default: dev]
    -a, --auto-approve      Auto-approve Terraform changes

EXAMPLES:
    $0                      Fix dev environment with prompts
    $0 -a                   Fix with auto-approval

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
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to get current security group
get_current_security_group() {
    cd "$TERRAFORM_DIR"
    
    print_info "Getting current security group ID..."
    
    # Get the security group ID from Terraform state
    local sg_id=$(terraform output -raw security_group_id 2>/dev/null || echo "")
    
    if [ -z "$sg_id" ]; then
        print_error "Could not get security group ID from Terraform"
        print_error "Please run this script from the terraform directory"
        exit 1
    fi
    
    print_success "Security Group ID: $sg_id"
    echo "$sg_id"
}

# Function to add DCV port rule manually
add_dcv_port_rule() {
    local sg_id=$1
    
    print_info "Adding DCV port 8443 rule to security group..."
    
    # Get your current public IP
    local my_ip=$(curl -s https://checkip.amazonaws.com/ 2>/dev/null || echo "0.0.0.0/0")
    
    if [[ "$my_ip" == "0.0.0.0/0" ]]; then
        print_warning "Could not determine your public IP, using 0.0.0.0/0"
        print_warning "This will allow access from anywhere (less secure)"
    else
        print_info "Your public IP: $my_ip"
    fi
    
    # Add the security group rule
    if aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 8443 \
        --cidr "$my_ip/32" \
        --description "NICE DCV access" 2>/dev/null; then
        
        print_success "✅ Added DCV port 8443 rule for $my_ip/32"
        return 0
    else
        print_error "❌ Failed to add security group rule"
        print_info "The rule might already exist or there was an AWS error"
        return 1
    fi
}

# Function to verify the rule was added
verify_rule_added() {
    local sg_id=$1
    
    print_info "Verifying DCV port rule was added..."
    
    # Check if port 8443 is now open
    local sg_rules=$(aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --query 'SecurityGroups[0].IpPermissions' \
        --output json 2>/dev/null || echo "[]")
    
    local dcv_port_open=$(echo "$sg_rules" | jq -r '.[] | select(.FromPort <= 8443 and .ToPort >= 8443 and .IpProtocol == "tcp") | .IpRanges[0].CidrIp // "0.0.0.0/0"')
    
    if [ -n "$dcv_port_open" ]; then
        print_success "✅ Port 8443 is now open in security group (allowed from: $dcv_port_open)"
        return 0
    else
        print_error "❌ Port 8443 is still not open in security group"
        return 1
    fi
}

# Function to test DCV connectivity
test_dcv_connectivity() {
    local public_ip=$1
    
    print_info "Testing DCV connectivity at https://$public_ip:8443 ..."
    
    # Wait a bit for the security group change to propagate
    print_info "Waiting 30 seconds for security group changes to propagate..."
    sleep 30
    
    # Test if port is open
    if timeout 10 bash -c "echo > /dev/tcp/$public_ip/8443" 2>/dev/null; then
        print_success "✅ DCV port 8443 is now accessible!"
        
        # Try to get DCV session info
        response=$(curl -sk --max-time 10 "https://$public_ip:8443/describe-session" 2>/dev/null || echo "")
        
        if [[ "$response" == *"session"* ]] || [[ "$response" == *"error"* ]] || [[ "$response" == *"unauthorized"* ]]; then
            print_success "✅ DCV server is responding!"
            return 0
        else
            print_warning "⚠️ DCV port is open but server might still be starting"
            return 1
        fi
    else
        print_error "❌ DCV port 8443 is still not accessible"
        return 1
    fi
}

# Function to apply Terraform changes
apply_terraform_changes() {
    cd "$TERRAFORM_DIR"
    
    print_info "Applying Terraform changes to make the fix permanent..."
    
    local apply_args=""
    if [[ "$AUTO_APPROVE" == true ]]; then
        apply_args="-auto-approve"
    fi
    
    if terraform apply -target=module.compute $apply_args; then
        print_success "✅ Terraform changes applied successfully"
        return 0
    else
        print_error "❌ Failed to apply Terraform changes"
        return 1
    fi
}

# Main function
main() {
    print_info "🔧 Quick Fix for DCV Port 8443 Connectivity Issue"
    print_info "Environment: $ENVIRONMENT"
    
    # Check prerequisites
    check_prerequisites
    
    # Get current security group
    local sg_id=$(get_current_security_group)
    
    # Add DCV port rule
    if add_dcv_port_rule "$sg_id"; then
        # Verify rule was added
        if verify_rule_added "$sg_id"; then
            # Get public IP for testing
            cd "$TERRAFORM_DIR"
            local public_ip=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
            
            if [ -n "$public_ip" ]; then
                print_success "✅ Security group rule added successfully!"
                print_info "Testing connectivity to $public_ip:8443..."
                
                # Test connectivity
                if test_dcv_connectivity "$public_ip"; then
                    print_success "🎉 DCV connectivity issue resolved!"
                    print_info ""
                    print_info "You can now access DCV at: https://$public_ip:8443"
                    print_info ""
                    print_info "Next steps:"
                    print_info "1. Open https://$public_ip:8443 in your browser"
                    print_info "2. Accept the self-signed certificate warning"
                    print_info "3. Login with Windows Administrator credentials"
                    print_info ""
                    print_info "To make this fix permanent, run:"
                    print_info "  cd $TERRAFORM_DIR && terraform apply"
                else
                    print_warning "⚠️ Port is open but DCV might still be starting"
                    print_info "Try accessing https://$public_ip:8443 in a few minutes"
                fi
            else
                print_warning "Could not get public IP for testing"
                print_info "The security group rule has been added successfully"
            fi
        else
            print_error "Failed to verify security group rule"
        fi
    else
        print_error "Failed to add security group rule"
        print_info "You may need to add it manually via AWS Console or run terraform apply"
    fi
    
    # Offer to apply Terraform changes
    echo ""
    if [[ "$AUTO_APPROVE" != true ]]; then
        read -p "Do you want to apply Terraform changes to make this fix permanent? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if apply_terraform_changes; then
                print_success "✅ Fix is now permanent in your Terraform configuration"
            fi
        fi
    else
        if apply_terraform_changes; then
            print_success "✅ Fix is now permanent in your Terraform configuration"
        fi
    fi
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
            TERRAFORM_DIR="$ENVIRONMENTS_DIR/$ENVIRONMENT"
            shift 2
            ;;
        -a|--auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
