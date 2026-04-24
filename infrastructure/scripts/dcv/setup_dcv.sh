#!/bin/bash

# AWS DCV (Desktop and Cloud Visualization) Setup Script for Windows EC2 via SSM
# This script provides SSM commands to deploy and execute the PowerShell DCV installation script
# Reference: https://docs.aws.amazon.com/pdfs/dcv/latest/adminguide/dcv-ag.pdf#setting-up-installing

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
LOG_FILE="$SCRIPT_DIR/dcv_setup.log"

# DCV Configuration (aligned with dcv_install.ps1)
DCV_SERVER_VERSION="2024.0-17979"
DCV_SESSION_NAME="ue5-session"
DCV_PORT="8443"
DCV_SESSION_OWNER="Administrator"

# PowerShell script configuration
POWERSHELL_SCRIPT_NAME="dcv_install.ps1"
POWERSHELL_SCRIPT_URL="https://raw.githubusercontent.com/YOUR_REPO/dcv_install.ps1"  # Only used for upload method

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_status $BLUE "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_status $RED "AWS CLI is not installed or not in PATH"
        print_status $YELLOW "Please install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_status $RED "AWS CLI is not configured"
        print_status $YELLOW "Please run: aws configure"
        exit 1
    fi
    
    # Check if instance ID is provided
    if [ -z "$INSTANCE_ID" ]; then
        print_status $RED "Instance ID is required"
        print_status $YELLOW "Usage: $0 <instance-id>"
        exit 1
    fi
    
    # Verify instance exists and is running
    local instance_state=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "not-found")
    
    if [ "$instance_state" = "not-found" ]; then
        print_status $RED "Instance $INSTANCE_ID not found or access denied"
        exit 1
    elif [ "$instance_state" != "running" ]; then
        print_status $RED "Instance $INSTANCE_ID is not running (current state: $instance_state)"
        exit 1
    fi
    
    print_status $GREEN "Prerequisites check passed"
    print_status $GREEN "Instance ID: $INSTANCE_ID"
    print_status $GREEN "Instance State: $instance_state"
    log_message "INFO" "Prerequisites check passed for instance $INSTANCE_ID"
}

# Function to check if PowerShell script exists locally
check_powershell_script() {
    local local_script="$SCRIPT_DIR/$POWERSHELL_SCRIPT_NAME"
    if [ ! -f "$local_script" ]; then
        print_status $RED "PowerShell script not found at: $local_script"
        print_status $YELLOW "Please ensure $POWERSHELL_SCRIPT_NAME is in the same directory as this script"
        print_status $YELLOW "For the base64 method, the script must be available locally"
        return 1
    fi
    print_status $GREEN "PowerShell script found: $local_script"
    return 0
}

# Function to deploy PowerShell script via SSM (Option A: Upload First, Then Execute)
deploy_via_ssm_upload() {
    print_status $BLUE "Deploying DCV installation via SSM (Upload First Method)..."
    
    # Step 1: Upload the PowerShell script to the instance
    print_status $YELLOW "Step 1: Uploading PowerShell script to instance..."
    local upload_command_id=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters "commands=[\"Invoke-WebRequest -Uri $POWERSHELL_SCRIPT_URL -OutFile C:\\\\$POWERSHELL_SCRIPT_NAME\"]" \
        --output text \
        --query 'Command.CommandId')
    
    if [ -z "$upload_command_id" ]; then
        print_status $RED "Failed to upload PowerShell script"
        exit 1
    fi
    
    print_status $GREEN "Upload command ID: $upload_command_id"
    log_message "INFO" "Upload command initiated with ID: $upload_command_id"
    
    # Wait for upload to complete
    print_status $YELLOW "Waiting for script upload to complete..."
    aws ssm wait command-executed --command-id "$upload_command_id" --instance-id "$INSTANCE_ID"
    
    # Check upload status
    local upload_status=$(aws ssm get-command-invocation --command-id "$upload_command_id" --instance-id "$INSTANCE_ID" --query 'Status' --output text)
    if [ "$upload_status" != "Success" ]; then
        print_status $RED "Script upload failed with status: $upload_status"
        exit 1
    fi
    
    print_status $GREEN "PowerShell script uploaded successfully"
    
    # Step 2: Execute the PowerShell script
    print_status $YELLOW "Step 2: Executing DCV installation script..."
    local execute_command_id=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters "commands=[\"Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force; C:\\\\$POWERSHELL_SCRIPT_NAME\"]" \
        --output text \
        --query 'Command.CommandId')
    
    if [ -z "$execute_command_id" ]; then
        print_status $RED "Failed to execute PowerShell script"
        exit 1
    fi
    
    print_status $GREEN "Execute command ID: $execute_command_id"
    log_message "INFO" "Execute command initiated with ID: $execute_command_id"
    
    # Store command IDs for monitoring
    echo "$execute_command_id" > "$SCRIPT_DIR/last_command_id.txt"
    
    print_status $GREEN "DCV installation command sent successfully"
    print_status $YELLOW "Use 'monitor_installation' function to check progress"
}

# Function to deploy PowerShell script via SSM (Option B: Base64 Encode and Send)
deploy_via_ssm_base64() {
    print_status $BLUE "Deploying DCV installation via SSM (Base64 Method)..."
    
    # Check if PowerShell script exists locally
    if ! check_powershell_script; then
        exit 1
    fi
    
    # Get the local script path
    local local_script="$SCRIPT_DIR/$POWERSHELL_SCRIPT_NAME"
    
    # Base64 encode the script
    print_status $YELLOW "Base64 encoding PowerShell script..."
    local base64_script=$(base64 -w 0 "$local_script")
    
    if [ -z "$base64_script" ]; then
        print_status $RED "Failed to base64 encode the script"
        exit 1
    fi
    
    print_status $GREEN "Script encoded successfully"
    
    # Send and execute in one command
    print_status $YELLOW "Sending and executing script via SSM..."
    local command_id=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters "commands=[\"[System.IO.File]::WriteAllText('C:\\\\$POWERSHELL_SCRIPT_NAME', [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$base64_script'))); Set-ExecutionPolicy RemoteSigned -Force; C:\\\\$POWERSHELL_SCRIPT_NAME\"]" \
        --output text \
        --query 'Command.CommandId')
    
    if [ -z "$command_id" ]; then
        print_status $RED "Failed to send command via SSM"
        exit 1
    fi
    
    print_status $GREEN "Command ID: $command_id"
    log_message "INFO" "Base64 deployment command initiated with ID: $command_id"
    
    # Store command ID for monitoring
    echo "$command_id" > "$SCRIPT_DIR/last_command_id.txt"
    
    print_status $GREEN "DCV installation command sent successfully"
    print_status $YELLOW "Use 'monitor_installation' function to check progress"
}

# Function to monitor installation progress
monitor_installation() {
    local command_id="$1"
    
    if [ -z "$command_id" ]; then
        # Try to get the last command ID
        if [ -f "$SCRIPT_DIR/last_command_id.txt" ]; then
            command_id=$(cat "$SCRIPT_DIR/last_command_id.txt")
        else
            print_status $RED "No command ID provided and no last command ID found"
            print_status $YELLOW "Usage: monitor_installation <command-id>"
            return 1
        fi
    fi
    
    print_status $BLUE "Monitoring installation progress for command ID: $command_id"
    
    # Check command status
    local status=$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$INSTANCE_ID" --query 'Status' --output text 2>/dev/null || echo "not-found")
    
    if [ "$status" = "not-found" ]; then
        print_status $RED "Command not found or access denied"
        return 1
    fi
    
    print_status $BLUE "Command Status: $status"
    
    case "$status" in
        "InProgress")
            print_status $YELLOW "Installation is still in progress..."
            ;;
        "Success")
            print_status $GREEN "Installation completed successfully!"
            ;;
        "Failed"|"Cancelled"|"TimedOut")
            print_status $RED "Installation failed with status: $status"
            ;;
        *)
            print_status $YELLOW "Unknown status: $status"
            ;;
    esac
    
    # Show command output
    print_status $BLUE "Command Output:"
    aws ssm get-command-invocation --command-id "$command_id" --instance-id "$INSTANCE_ID" --query 'StandardOutputContent' --output text
    
    if [ "$status" = "Failed" ]; then
        print_status $RED "Error Output:"
        aws ssm get-command-invocation --command-id "$command_id" --instance-id "$INSTANCE_ID" --query 'StandardErrorContent' --output text
    fi
    
    return 0
}

# Function to check installation logs
check_installation_logs() {
    print_status $BLUE "Checking DCV installation logs on instance..."
    
    local log_command_id=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=["Get-Content C:\\logs\\dcv-install.log -Tail 50"]' \
        --output text \
        --query 'Command.CommandId')
    
    if [ -z "$log_command_id" ]; then
        print_status $RED "Failed to retrieve logs"
        return 1
    fi
    
    print_status $GREEN "Log command ID: $log_command_id"
    print_status $YELLOW "Waiting for log retrieval..."
    
    # Wait for command to complete
    aws ssm wait command-executed --command-id "$log_command_id" --instance-id "$INSTANCE_ID"
    
    # Display logs
    print_status $BLUE "Recent DCV Installation Logs:"
    aws ssm get-command-invocation --command-id "$log_command_id" --instance-id "$INSTANCE_ID" --query 'StandardOutputContent' --output text
    
    return 0
}

# Function to get instance connection information
get_connection_info() {
    print_status $BLUE "Getting instance connection information..."
    
    # Get public IP
    local public_ip=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || echo "N/A")
    
    # Get private IP
    local private_ip=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo "N/A")
    
    print_status $GREEN "Instance Connection Information:"
    print_status $BLUE "Instance ID: $INSTANCE_ID"
    print_status $BLUE "Public IP: $public_ip"
    print_status $BLUE "Private IP: $private_ip"
    print_status $BLUE "DCV Port: $DCV_PORT"
    print_status $BLUE "Session Name: $DCV_SESSION_NAME"
    print_status $BLUE "Session Owner: $DCV_SESSION_OWNER"
    
    if [ "$public_ip" != "N/A" ] && [ "$public_ip" != "None" ]; then
        print_status $GREEN "DCV Connection URL: https://$public_ip:$DCV_PORT"
    else
        print_status $YELLOW "No public IP found. Use private IP or VPN to connect."
        print_status $YELLOW "DCV Connection URL: https://$private_ip:$DCV_PORT"
    fi
    
    log_message "INFO" "Connection info retrieved for instance $INSTANCE_ID"
}


# Function to display usage information
show_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy-upload <instance-id>     Deploy DCV via SSM (Upload First Method)"
    echo "  deploy-base64 <instance-id>     Deploy DCV via SSM (Base64 Method)"
    echo "  monitor <instance-id> [cmd-id]  Monitor installation progress"
    echo "  logs <instance-id>              Check installation logs"
    echo "  info <instance-id>              Get connection information"
    echo "  help                            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy-upload i-0a0cf65b6a9a9b7d0"
    echo "  $0 deploy-base64 i-0a0cf65b6a9a9b7d0"
    echo "  $0 monitor i-0a0cf65b6a9a9b7d0"
    echo "  $0 logs i-0a0cf65b6a9a9b7d0"
    echo "  $0 info i-0a0cf65b6a9a9b7d0"
    echo ""
    echo "Prerequisites:"
    echo "  - AWS CLI installed and configured"
    echo "  - SSM agent running on target instance"
    echo "  - Appropriate IAM permissions for SSM"
    echo ""
    echo "For the base64 method, ensure dcv_install.ps1 is in the same directory as this script."
}

# Main execution function
main() {
    local command="$1"
    INSTANCE_ID="$2"
    
    # Initialize log file
    echo "AWS DCV SSM Deployment Log - $(date)" > "$LOG_FILE"
    
    case "$command" in
        "deploy-upload")
            if [ -z "$INSTANCE_ID" ]; then
                print_status $RED "Instance ID required for deploy-upload command"
                show_usage
                exit 1
            fi
            print_status $GREEN "Starting DCV deployment via SSM (Upload Method)"
            print_status $GREEN "=============================================="
            check_prerequisites
            deploy_via_ssm_upload
            get_connection_info
            ;;
        "deploy-base64")
            if [ -z "$INSTANCE_ID" ]; then
                print_status $RED "Instance ID required for deploy-base64 command"
                show_usage
                exit 1
            fi
            print_status $GREEN "Starting DCV deployment via SSM (Base64 Method)"
            print_status $GREEN "=============================================="
            check_prerequisites
            deploy_via_ssm_base64
            get_connection_info
            ;;
        "monitor")
            if [ -z "$INSTANCE_ID" ]; then
                print_status $RED "Instance ID required for monitor command"
                show_usage
                exit 1
            fi
            print_status $GREEN "Monitoring DCV installation progress"
            print_status $GREEN "===================================="
            check_prerequisites
            monitor_installation "$3"
            ;;
        "logs")
            if [ -z "$INSTANCE_ID" ]; then
                print_status $RED "Instance ID required for logs command"
                show_usage
                exit 1
            fi
            print_status $GREEN "Checking DCV installation logs"
            print_status $GREEN "=============================="
            check_prerequisites
            check_installation_logs
            ;;
        "info")
            if [ -z "$INSTANCE_ID" ]; then
                print_status $RED "Instance ID required for info command"
                show_usage
                exit 1
            fi
            print_status $GREEN "Getting instance connection information"
            print_status $GREEN "======================================="
            check_prerequisites
            get_connection_info
            ;;
        "help"|"-h"|"--help"|"")
            show_usage
            ;;
        *)
            print_status $RED "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
    
    print_status $GREEN "Operation completed!"
    print_status $BLUE "Check the log file for detailed information: $LOG_FILE"
}

# Execute main function
main "$@"
