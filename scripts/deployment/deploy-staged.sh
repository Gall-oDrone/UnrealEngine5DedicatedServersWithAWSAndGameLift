#!/bin/bash

# Staged Deployment Script for Unreal Engine 5 Infrastructure with NiceDCV
# This script deploys the infrastructure in stages with proper verification

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
TERRAFORM_DIR="$ENVIRONMENTS_DIR/dev"

# Default values
ENVIRONMENT="dev"
AUTO_APPROVE=false
SKIP_DCV_CHECK=false

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

Deploy Unreal Engine 5 infrastructure with NiceDCV in stages.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to deploy (dev, staging, prod) [default: dev]
    -a, --auto-approve      Auto-approve Terraform changes
    --skip-dcv-check        Skip DCV connectivity check
    -d, --destroy           Destroy the infrastructure

EXAMPLES:
    $0                      Deploy dev environment with prompts
    $0 -a                   Deploy with auto-approval
    $0 --skip-dcv-check     Deploy without checking DCV connectivity
    $0 -d                   Destroy infrastructure

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

# Function to wait for EC2 instance to be ready
wait_for_instance() {
    local instance_id=$1
    local max_wait=${2:-600}  # Default 10 minutes
    
    local elapsed=0
    local interval=10
    
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
        
        if [[ "$instance_state" == "running" ]] && [[ "$status_checks" == "ok" ]]; then
            print_success "Instance $instance_id is ready!"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        
        if [ $((elapsed % 30)) -eq 0 ]; then
            print_info "Instance state: $instance_state, Status checks: $status_checks ($elapsed seconds elapsed)"
        fi
    done
    
    print_warning "Timeout waiting for instance $instance_id"
    return 1
}

# Function to wait for Windows user data to complete
wait_for_userdata() {
    local instance_id=$1
    local max_wait=${2:-1800}  # Default 30 minutes for UE5 compilation
    
    local elapsed=0
    local interval=30
    
    print_info "⏳ Waiting for Windows user data script to complete (this may take 20-30 minutes)..."
    print_info "The script is installing Visual Studio, Unreal Engine dependencies, and NiceDCV..."
    
    while [ $elapsed -lt $max_wait ]; do
        # Try to get the status from CloudWatch logs or SSM
        # For Windows, we can check if the setup completion file exists
        
        # Check if we can reach the instance via SSM
        if aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$instance_id" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null | grep -q "Online"; then
            
            print_info "Instance is online via SSM. Checking completion status..."
            
            # Try to check if setup is complete using SSM
            completion_check=$(aws ssm send-command \
                --instance-ids "$instance_id" \
                --document-name "AWS-RunPowerShellScript" \
                --parameters 'commands=["Test-Path C:\logs\setup-complete.txt"]' \
                --query 'Command.CommandId' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$completion_check" ]; then
                sleep 5
                result=$(aws ssm get-command-invocation \
                    --command-id "$completion_check" \
                    --instance-id "$instance_id" \
                    --query 'StandardOutputContent' \
                    --output text 2>/dev/null || echo "False")
                
                if [[ "$result" == *"True"* ]]; then
                    print_success "✅ User data script completed successfully!"
                    return 0
                fi
            fi
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        
        # Progress updates
        if [ $((elapsed % 120)) -eq 0 ]; then  # Every 2 minutes
            print_info "Still waiting for setup to complete... ($((elapsed / 60)) minutes elapsed)"
            print_info "Setup stages: Chocolatey → Visual Studio → UE5 Prerequisites → NiceDCV → Completion"
        fi
    done
    
    print_warning "Timeout waiting for user data completion after $((max_wait / 60)) minutes"
    print_warning "The setup might still be running. Check C:\\logs\\ue5-setup.log on the instance."
    return 1
}

# Function to test DCV connectivity
test_dcv_connectivity() {
    local public_ip=$1
    local dcv_port=8443
    
    print_info "Testing DCV connectivity at https://$public_ip:$dcv_port ..."
    
    # Test if port is open
    if timeout 5 bash -c "echo > /dev/tcp/$public_ip/$dcv_port" 2>/dev/null; then
        print_success "✅ DCV port $dcv_port is open"
        
        # Try to get DCV session info (will fail with auth error but proves DCV is running)
        response=$(curl -sk --max-time 5 "https://$public_ip:$dcv_port/describe-session" 2>/dev/null || echo "")
        
        if [[ "$response" == *"session"* ]] || [[ "$response" == *"error"* ]] || [[ "$response" == *"unauthorized"* ]]; then
            print_success "✅ DCV server is responding"
            return 0
        else
            print_warning "⚠️ DCV port is open but server might still be starting"
            return 1
        fi
    else
        print_warning "⚠️ DCV port $dcv_port is not accessible yet"
        return 1
    fi
}

# Function to get RDP password
get_rdp_password() {
    local instance_id=$1
    local key_path=$2
    
    print_info "Retrieving Windows Administrator password..."
    
    if [ -z "$key_path" ] || [ ! -f "$key_path" ]; then
        print_warning "No key pair specified or key file not found."
        print_info "Password will be auto-generated. Check AWS Console for password."
        return
    fi
    
    # Get encrypted password
    encrypted_password=$(aws ec2 get-password-data \
        --instance-id "$instance_id" \
        --query 'PasswordData' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$encrypted_password" ]; then
        print_warning "Password not yet available. It may take up to 4 minutes after launch."
        return
    fi
    
    # Decrypt password
    password=$(echo "$encrypted_password" | base64 -d | openssl rsautl -decrypt -inkey "$key_path" 2>/dev/null || echo "")
    
    if [ -n "$password" ]; then
        print_success "Administrator password retrieved successfully"
        echo "Password: $password"
    else
        print_warning "Could not decrypt password. Check your key file."
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
    print_info "📦 Stage 2: Deploying compute infrastructure (EC2 instance with UE5 and DCV setup)..."
    
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
    
    # Stage 3: Wait for Instance and Setup
    print_info "📦 Stage 3: Waiting for instance and setup scripts..."
    
    # Wait for instance to be ready
    wait_for_instance "$INSTANCE_ID"
    
    # Wait for user data to complete (includes UE5 and DCV setup)
    if wait_for_userdata "$INSTANCE_ID"; then
        print_success "✅ Instance setup completed!"
    else
        print_warning "⚠️ Setup might still be running. Continuing..."
    fi
    
    # Stage 4: Deploy Monitoring
    print_info "📦 Stage 4: Deploying monitoring infrastructure..."
    
    terraform apply $apply_args
    
    print_success "Full infrastructure deployed"
    
    # Stage 5: Verify DCV Connectivity
    if [[ "$SKIP_DCV_CHECK" != true ]]; then
        print_info "📦 Stage 5: Verifying DCV connectivity..."
        
        # Wait a bit for DCV to fully start
        print_info "Waiting 60 seconds for DCV services to fully initialize..."
        sleep 60
        
        if test_dcv_connectivity "$PUBLIC_IP"; then
            print_success "✅ DCV is accessible!"
        else
            print_warning "⚠️ DCV might still be starting. Try accessing it manually in a few minutes."
        fi
    fi
}

# Function to destroy infrastructure
destroy_infrastructure() {
    cd "$TERRAFORM_DIR"
    
    print_warning "⚠️ WARNING: This will destroy all infrastructure!"
    
    if [[ "$AUTO_APPROVE" != true ]]; then
        read -p "Are you sure you want to destroy the infrastructure? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            print_info "Destruction cancelled"
            exit 0
        fi
    fi
    
    local destroy_args=""
    if [[ "$AUTO_APPROVE" == true ]]; then
        destroy_args="-auto-approve"
    fi
    
    terraform destroy $destroy_args
    
    print_success "Infrastructure destroyed"
}

# Parse command line arguments
DESTROY=false
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
        --skip-dcv-check)
            SKIP_DCV_CHECK=true
            shift
            ;;
        -d|--destroy)
            DESTROY=true
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
    print_info "🚀 Starting Unreal Engine 5 infrastructure deployment with NiceDCV"
    print_info "Environment: $ENVIRONMENT"
    
    # Check prerequisites
    check_prerequisites
    
    if [[ "$DESTROY" == true ]]; then
        destroy_infrastructure
    else
        # Deploy infrastructure
        deploy_infrastructure
        
        # Get final outputs
        cd "$TERRAFORM_DIR"
        print_success "✅ Deployment complete!"
        
        INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null || echo "")
        PUBLIC_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
        KEY_NAME=$(terraform output -raw key_pair_name 2>/dev/null || echo "")
        
        # Display connection information
        print_info "═══════════════════════════════════════════════════════════════"
        print_info "Connection Information:"
        print_info "═══════════════════════════════════════════════════════════════"
        echo ""
        print_success "Instance ID: $INSTANCE_ID"
        print_success "Public IP: $PUBLIC_IP"
        echo ""
        print_info "📱 Remote Desktop (RDP):"
        echo "  - Address: $PUBLIC_IP"
        echo "  - Port: 3389"
        echo "  - Username: Administrator"
        echo ""
        print_info "🖥️ NICE DCV (High-performance remote desktop):"
        echo "  - URL: https://$PUBLIC_IP:8443"
        echo "  - Session: ue5-session"
        echo "  - Note: Accept the self-signed certificate warning"
        echo ""
        print_info "📂 Unreal Engine Location:"
        echo "  - Path: C:\\UnrealEngine\\UnrealEngine"
        echo "  - Editor: C:\\UnrealEngine\\UnrealEngine\\Engine\\Binaries\\Win64\\UnrealEditor.exe"
        echo "  - Logs: C:\\logs\\"
        echo ""
        print_info "🔐 Getting Administrator Password:"
        
        # Try to get password if key is available
        if [ -n "$KEY_NAME" ]; then
            KEY_PATH="~/.ssh/${KEY_NAME}.pem"
            KEY_PATH=$(eval echo "$KEY_PATH")
            if [ -f "$KEY_PATH" ]; then
                get_rdp_password "$INSTANCE_ID" "$KEY_PATH"
            else
                echo "  1. Go to EC2 Console"
                echo "  2. Right-click instance $INSTANCE_ID"
                echo "  3. Select 'Get Windows password'"
                echo "  4. Upload your private key or wait for auto-generated password"
            fi
        else
            echo "  1. Go to EC2 Console"
            echo "  2. Right-click instance $INSTANCE_ID"
            echo "  3. Select 'Get Windows password'"
            echo "  4. Wait ~4 minutes after instance launch"
        fi
        echo ""
        print_info "═══════════════════════════════════════════════════════════════"
        
        # Provide helpful commands
        print_info "📝 Useful AWS CLI commands:"
        echo "  - Check instance: aws ec2 describe-instances --instance-ids $INSTANCE_ID"
        echo "  - Get password: aws ec2 get-password-data --instance-id $INSTANCE_ID"
        echo "  - Check logs: aws ssm send-command --instance-ids $INSTANCE_ID --document-name \"AWS-RunPowerShellScript\" --parameters 'commands=[\"Get-Content C:\\logs\\ue5-setup.log -Tail 50\"]'"
        echo ""
        print_info "💡 Tips:"
        echo "  - Initial setup takes 20-30 minutes (Visual Studio, UE5, DCV installation)"
        echo "  - Check C:\\logs\\setup-complete.txt to verify completion"
        echo "  - DCV provides better performance than standard RDP for graphics"
        echo "  - Consider using spot instances for cost savings (up to 90% discount)"
        echo ""
        
        # Optional: Open DCV URL in browser
        if [[ "$SKIP_DCV_CHECK" != true ]]; then
            read -p "Do you want to open DCV in your browser? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if command -v xdg-open &> /dev/null; then
                    xdg-open "https://$PUBLIC_IP:8443"
                elif command -v open &> /dev/null; then
                    open "https://$PUBLIC_IP:8443"
                else
                    print_info "Please open https://$PUBLIC_IP:8443 in your browser"
                fi
            fi
        fi
    fi
}

# Run main function
main "$@"