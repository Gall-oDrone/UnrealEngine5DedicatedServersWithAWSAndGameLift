#!/bin/bash

# DCV Debugging Script for Unreal Engine 5 Infrastructure
# This script helps troubleshoot DCV connectivity issues

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
INSTANCE_ID=""
PUBLIC_IP=""

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

Debug DCV connectivity issues for Unreal Engine 5 infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to debug (dev, staging, prod) [default: dev]
    -i, --instance-id       Specific EC2 instance ID to debug
    -p, --public-ip         Specific public IP address to debug

EXAMPLES:
    $0                      Debug current dev environment
    $0 -i i-1234567890      Debug specific instance
    $0 -p 1.2.3.4          Debug specific IP address

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
    
    # Check netcat for port testing
    if ! command -v nc &> /dev/null; then
        missing_tools+=("netcat")
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

# Function to get instance details from Terraform
get_instance_details() {
    cd "$TERRAFORM_DIR"
    
    if [ -z "$INSTANCE_ID" ]; then
        print_info "Getting instance details from Terraform..."
        INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null || echo "")
    fi
    
    if [ -z "$PUBLIC_IP" ]; then
        print_info "Getting public IP from Terraform..."
        PUBLIC_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
    fi
    
    if [ -z "$INSTANCE_ID" ] || [ -z "$PUBLIC_IP" ]; then
        print_error "Failed to get instance details from Terraform"
        print_error "Please provide instance ID and public IP manually"
        exit 1
    fi
    
    print_success "Instance ID: $INSTANCE_ID"
    print_success "Public IP: $PUBLIC_IP"
}

# Function to check instance status
check_instance_status() {
    print_info "🔍 Checking EC2 instance status..."
    
    local instance_state=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "unknown")
    
    local status_checks=$(aws ec2 describe-instance-status \
        --instance-ids "$INSTANCE_ID" \
        --query 'InstanceStatuses[0].InstanceStatus.Status' \
        --output text 2>/dev/null || echo "unknown")
    
    print_info "Instance State: $instance_state"
    print_info "Status Checks: $status_checks"
    
    if [[ "$instance_state" != "running" ]]; then
        print_error "❌ Instance is not running (state: $instance_state)"
        return 1
    fi
    
    if [[ "$status_checks" != "ok" ]]; then
        print_warning "⚠️ Instance status checks are not OK (status: $status_checks)"
        return 1
    fi
    
    print_success "✅ Instance is running and healthy"
    return 0
}

# Function to check security group rules
check_security_groups() {
    print_info "🔍 Checking security group rules..."
    
    local sg_id=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$sg_id" ]; then
        print_error "❌ Could not get security group ID"
        return 1
    fi
    
    print_info "Security Group ID: $sg_id"
    
    # Get security group rules
    local sg_rules=$(aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --query 'SecurityGroups[0].IpPermissions' \
        --output json 2>/dev/null || echo "[]")
    
    print_info "Security Group Rules:"
    echo "$sg_rules" | jq -r '.[] | "  - \(.IpProtocol) \(.FromPort)-\(.ToPort) (\(.IpRanges[0].CidrIp // "0.0.0.0/0"))"'
    
    # Check if port 8443 is open
    local dcv_port_open=$(echo "$sg_rules" | jq -r '.[] | select(.FromPort <= 8443 and .ToPort >= 8443 and .IpProtocol == "tcp") | .IpRanges[0].CidrIp // "0.0.0.0/0"')
    
    if [ -n "$dcv_port_open" ]; then
        print_success "✅ Port 8443 is open in security group (allowed from: $dcv_port_open)"
    else
        print_error "❌ Port 8443 is NOT open in security group"
        print_info "This is likely the root cause of your connectivity issue"
    fi
}

# Function to check Windows Firewall via SSM
check_windows_firewall() {
    print_info "🔍 Checking Windows Firewall rules via SSM..."
    
    # Check if instance is online via SSM
    local ssm_status=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "Offline")
    
    if [[ "$ssm_status" != "Online" ]]; then
        print_warning "⚠️ Instance is not online via SSM (status: $ssm_status)"
        print_info "Cannot check Windows Firewall rules remotely"
        return 1
    fi
    
    print_info "Instance is online via SSM, checking firewall rules..."
    
    # Check DCV firewall rules
    local firewall_check=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=["Get-NetFirewallRule -DisplayName \"DCV*\" | Select-Object DisplayName, Enabled, Direction, Action, Protocol, LocalPort | Format-Table"]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$firewall_check" ]; then
        sleep 5
        local result=$(aws ssm get-command-invocation \
            --command-id "$firewall_check" \
            --instance-id "$INSTANCE_ID" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$result" ]; then
            print_info "Windows Firewall Rules for DCV:"
            echo "$result"
        else
            print_warning "⚠️ No firewall rules found for DCV"
        fi
    fi
}

# Function to check DCV service status via SSM
check_dcv_services() {
    print_info "🔍 Checking DCV service status via SSM..."
    
    local ssm_status=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "Offline")
    
    if [[ "$ssm_status" != "Online" ]]; then
        print_warning "⚠️ Instance is not online via SSM (status: $ssm_status)"
        return 1
    fi
    
    # Check DCV services
    local service_check=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=["Get-Service -Name \"DCV*\" | Select-Object Name, Status, StartType | Format-Table"]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$service_check" ]; then
        sleep 5
        local result=$(aws ssm get-command-invocation \
            --command-id "$service_check" \
            --instance-id "$INSTANCE_ID" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$result" ]; then
            print_info "DCV Services Status:"
            echo "$result"
        else
            print_warning "⚠️ No DCV services found"
        fi
    fi
    
    # Check if DCV is listening on port 8443
    local port_check=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=["netstat -an | findstr :8443"]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$port_check" ]; then
        sleep 5
        local result=$(aws ssm get-command-invocation \
            --command-id "$port_check" \
            --instance-id "$INSTANCE_ID" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$result" ]; then
            print_info "Port 8443 Status:"
            echo "$result"
        else
            print_warning "⚠️ Nothing listening on port 8443"
        fi
    fi
}

# Function to test network connectivity
test_network_connectivity() {
    print_info "🔍 Testing network connectivity..."
    
    # Test basic connectivity
    if ping -c 3 "$PUBLIC_IP" &> /dev/null; then
        print_success "✅ Basic connectivity to $PUBLIC_IP is working"
    else
        print_error "❌ Basic connectivity to $PUBLIC_IP is failing"
        return 1
    fi
    
    # Test RDP port
    if timeout 5 bash -c "echo > /dev/tcp/$PUBLIC_IP/3389" 2>/dev/null; then
        print_success "✅ RDP port 3389 is accessible"
    else
        print_warning "⚠️ RDP port 3389 is not accessible"
    fi
    
    # Test DCV port
    if timeout 5 bash -c "echo > /dev/tcp/$PUBLIC_IP/8443" 2>/dev/null; then
        print_success "✅ DCV port 8443 is accessible"
    else
        print_error "❌ DCV port 8443 is not accessible"
        print_info "This confirms the connectivity issue"
    fi
    
    # Test HTTP port
    if timeout 5 bash -c "echo > /dev/tcp/$PUBLIC_IP/80" 2>/dev/null; then
        print_success "✅ HTTP port 80 is accessible"
    else
        print_warning "⚠️ HTTP port 80 is not accessible"
    fi
}

# Function to check setup logs
check_setup_logs() {
    print_info "🔍 Checking setup logs via SSM..."
    
    local ssm_status=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "Offline")
    
    if [[ "$ssm_status" != "Online" ]]; then
        print_warning "⚠️ Instance is not online via SSM (status: $ssm_status)"
        return 1
    fi
    
    # Check setup completion
    local completion_check=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=["Test-Path C:\logs\setup-complete.txt"]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$completion_check" ]; then
        sleep 5
        local result=$(aws ssm get-command-invocation \
            --command-id "$completion_check" \
            --instance-id "$INSTANCE_ID" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "False")
        
        if [[ "$result" == *"True"* ]]; then
            print_success "✅ Setup completion marker found"
        else
            print_warning "⚠️ Setup completion marker not found - setup may still be running"
        fi
    fi
    
    # Check DCV setup log
    local dcv_log_check=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=["Get-Content C:\logs\dcv-setup.log -Tail 20 -ErrorAction SilentlyContinue"]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$dcv_log_check" ]; then
        sleep 5
        local result=$(aws ssm get-command-invocation \
            --command-id "$dcv_log_check" \
            --instance-id "$INSTANCE_ID" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$result" ]; then
            print_info "Last 20 lines of DCV setup log:"
            echo "$result"
        else
            print_warning "⚠️ DCV setup log not found or empty"
        fi
    fi
}

# Function to provide recommendations
provide_recommendations() {
    print_info "💡 Recommendations to fix DCV connectivity:"
    echo ""
    echo "1. 🔧 IMMEDIATE FIX - Update Security Group:"
    echo "   - Add ingress rule for port 8443 (TCP) from your IP"
    echo "   - Or run: terraform apply to apply the updated configuration"
    echo ""
    echo "2. 🔍 Check DCV Service:"
    echo "   - Verify DCV Server service is running on the instance"
    echo "   - Check Windows Firewall allows port 8443"
    echo ""
    echo "3. 📝 Check Setup Status:"
    echo "   - Verify setup-complete.txt exists in C:\logs\"
    echo "   - Check DCV setup logs for errors"
    echo ""
    echo "4. 🌐 Test Connectivity:"
    echo "   - Try connecting from different network (mobile hotspot)"
    echo "   - Check if your ISP/network blocks port 8443"
    echo ""
    echo "5. 🔄 Re-deploy if needed:"
    echo "   - Run: terraform destroy && terraform apply"
    echo "   - This will apply the security group fix"
}

# Main debugging function
main() {
    print_info "🔍 Starting DCV connectivity debugging for Unreal Engine 5 infrastructure"
    print_info "Environment: $ENVIRONMENT"
    
    # Check prerequisites
    check_prerequisites
    
    # Get instance details
    get_instance_details
    
    echo ""
    print_info "═══════════════════════════════════════════════════════════════"
    print_info "Debugging Results:"
    print_info "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Run all checks
    check_instance_status
    echo ""
    
    check_security_groups
    echo ""
    
    check_windows_firewall
    echo ""
    
    check_dcv_services
    echo ""
    
    test_network_connectivity
    echo ""
    
    check_setup_logs
    echo ""
    
    print_info "═══════════════════════════════════════════════════════════════"
    print_info "Summary and Recommendations:"
    print_info "═══════════════════════════════════════════════════════════════"
    echo ""
    
    provide_recommendations
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
        -i|--instance-id)
            INSTANCE_ID="$2"
            shift 2
            ;;
        -p|--public-ip)
            PUBLIC_IP="$2"
            shift 2
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
