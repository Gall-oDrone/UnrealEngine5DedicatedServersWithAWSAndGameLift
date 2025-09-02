#!/bin/bash

# Enhanced Staged Deployment Script with Better Progress Tracking
# This script deploys the infrastructure with detailed progress monitoring

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

print_progress() {
    echo -e "${CYAN}[PROGRESS]${NC} $1"
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

# Enhanced function to monitor user data progress
monitor_userdata_progress() {
    local instance_id=$1
    local max_wait=${2:-2400}  # Default 40 minutes for full installation
    
    local elapsed=0
    local interval=20
    local last_progress=""
    
    print_info "⏳ Monitoring Windows setup progress..."
    print_info "Installation stages: Prerequisites → DCV Installation → Configuration → Completion"
    
    while [ $elapsed -lt $max_wait ]; do
        # Wait for SSM to be available
        local ssm_status=$(aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$instance_id" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null || echo "Offline")
        
        if [[ "$ssm_status" == "Online" ]]; then
            # Check multiple progress markers
            local progress_check=$(aws ssm send-command \
                --instance-ids "$instance_id" \
                --document-name "AWS-RunPowerShellScript" \
                --parameters 'commands=[
                    "$stages = @()",
                    "if (Test-Path \"C:\\logs\\stage-prerequisites.txt\") { $stages += \"Prerequisites\" }",
                    "if (Test-Path \"C:\\logs\\stage-dcv-download.txt\") { $stages += \"DCV-Download\" }",
                    "if (Test-Path \"C:\\logs\\stage-dcv-install.txt\") { $stages += \"DCV-Install\" }",
                    "if (Test-Path \"C:\\logs\\stage-dcv-config.txt\") { $stages += \"DCV-Config\" }",
                    "if (Test-Path \"C:\\logs\\dcv-install-complete.txt\") { $stages += \"Complete\" }",
                    "if ($stages.Count -eq 0) { \"Starting\" } else { $stages -join \",\" }"
                ]' \
                --query 'Command.CommandId' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$progress_check" ]; then
                sleep 5
                local current_progress=$(aws ssm get-command-invocation \
                    --command-id "$progress_check" \
                    --instance-id "$instance_id" \
                    --query 'StandardOutputContent' \
                    --output text 2>/dev/null || echo "Unknown")
                
                # Only print if progress changed
                if [[ "$current_progress" != "$last_progress" ]]; then
                    print_progress "Current stage: $current_progress"
                    last_progress="$current_progress"
                fi
                
                # Check if complete
                if [[ "$current_progress" == *"Complete"* ]]; then
                    print_success "✅ Setup completed successfully!"
                    
                    # Get installation summary
                    print_info "Retrieving installation summary..."
                    local summary_check=$(aws ssm send-command \
                        --instance-ids "$instance_id" \
                        --document-name "AWS-RunPowerShellScript" \
                        --parameters 'commands=["Get-Content C:\\logs\\dcv-install-complete.txt -ErrorAction SilentlyContinue"]' \
                        --query 'Command.CommandId' \
                        --output text 2>/dev/null || echo "")
                    
                    if [ -n "$summary_check" ]; then
                        sleep 5
                        local summary=$(aws ssm get-command-invocation \
                            --command-id "$summary_check" \
                            --instance-id "$instance_id" \
                            --query 'StandardOutputContent' \
                            --output text 2>/dev/null || echo "")
                        
                        if [ -n "$summary" ]; then
                            echo ""
                            echo "$summary"
                            echo ""
                        fi
                    fi
                    
                    return 0
                fi
            fi
            
            # Check for errors in log
            if [ $((elapsed % 60)) -eq 0 ]; then
                local error_check=$(aws ssm send-command \
                    --instance-ids "$instance_id" \
                    --document-name "AWS-RunPowerShellScript" \
                    --parameters 'commands=["Get-Content C:\\logs\\dcv-install.log -Tail 5 -ErrorAction SilentlyContinue | Select-String -Pattern \"ERROR\",\"Failed\""]' \
                    --query 'Command.CommandId' \
                    --output text 2>/dev/null || echo "")
                
                if [ -n "$error_check" ]; then
                    sleep 5
                    local errors=$(aws ssm get-command-invocation \
                        --command-id "$error_check" \
                        --instance-id "$instance_id" \
                        --query 'StandardOutputContent' \
                        --output text 2>/dev/null || echo "")
                    
                    if [ -n "$errors" ] && [[ "$errors" != "null" ]]; then
                        print_warning "Errors detected in installation log:"
                        echo "$errors"
                    fi
                fi
            fi
        else
            if [ $((elapsed % 30)) -eq 0 ]; then
                print_info "Waiting for SSM agent to come online (status: $ssm_status)..."
            fi
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        
        # Progress updates
        if [ $((elapsed % 120)) -eq 0 ]; then
            print_info "Still monitoring setup... ($((elapsed / 60)) minutes elapsed)"
        fi
    done
    
    print_warning "Timeout after $((max_wait / 60)) minutes"
    print_warning "Setup might still be running. Attempting to get latest status..."
    
    # Try to get final status
    local final_check=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=["Get-Content C:\\logs\\dcv-install.log -Tail 20 -ErrorAction SilentlyContinue"]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$final_check" ]; then
        sleep 5
        local final_log=$(aws ssm get-command-invocation \
            --command-id "$final_check" \
            --instance-id "$instance_id" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$final_log" ]; then
            print_info "Last 20 lines of installation log:"
            echo "$final_log"
        fi
    fi
    
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
    print_info "📦 Stage 2: Deploying compute infrastructure (EC2 instance with DCV setup)..."
    
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
    
    # Monitor user data progress with enhanced tracking
    if monitor_userdata_progress "$INSTANCE_ID"; then
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
        print_info "Waiting 30 seconds for DCV services to fully initialize..."
        sleep 30
        
        if test_dcv_connectivity "$PUBLIC_IP"; then
            print_success "✅ DCV is accessible!"
        else
            print_warning "⚠️ DCV might still be starting. Try accessing it manually in a few minutes."
        fi
    fi
}

# Parse command line arguments (rest of the script remains the same...)
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
    print_info "🚀 Starting infrastructure deployment with NiceDCV"
    print_info "Environment: $ENVIRONMENT"
    
    # Check prerequisites
    check_prerequisites
    
    if [[ "$DESTROY" == true ]]; then
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
        print_info "═══════════════════════════════════════════════════════════════"
    fi
}

# Run main function
main "$@"