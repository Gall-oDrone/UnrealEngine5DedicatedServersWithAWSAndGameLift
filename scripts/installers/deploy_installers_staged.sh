#!/bin/bash

# Staged Installer Deployment Script for Windows EC2 via SSM
# This script deploys installers from S3 URLs to Windows instances in stages with progress monitoring
# Combines the staged deployment logic from deploy-staged.sh with installer deployment from setup_dcv.sh

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
LOG_FILE="$SCRIPT_DIR/installer_deployment.log"

# Default values
ENVIRONMENT="dev"
AUTO_APPROVE=false
SKIP_INSTALLER_CHECK=false
DESTROY=false

# Array of S3 installer URLs (you can modify these as needed)
declare -a INSTALLER_URLS=(
    # Add your S3 installer URLs here
    # Example: "https://s3.amazonaws.com/your-bucket/installers/NiceDCV/Amazon DCV 2024.0 Client/Windows x86_64/Version 2024.0-9431/nice-dcv-client-Release.msi"
    # Example: "https://s3.amazonaws.com/your-bucket/installers/CMake/Windows x86_64/Version 4.1.1/cmake-4.1.1-windows-x86_64.msi"
    # Leave empty for now as requested
)

# Array of installer names (corresponding to INSTALLER_URLS array)
declare -a INSTALLER_NAMES=(
    # Add descriptive names for your installers
    # Example: "NiceDCV Client"
    # Example: "CMake"
    # Leave empty for now as requested
)

# Array of installer types (msi, exe, zip, etc.)
declare -a INSTALLER_TYPES=(
    # Add installer types corresponding to URLs
    # Example: "msi"
    # Example: "msi"
    # Leave empty for now as requested
)

# PowerShell script for installer execution
POWERSHELL_SCRIPT_NAME="installer_deploy.ps1"

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_message "INFO" "$1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_message "SUCCESS" "$1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_message "WARNING" "$1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_message "ERROR" "$1"
}

print_progress() {
    echo -e "${CYAN}[PROGRESS]${NC} $1"
    log_message "PROGRESS" "$1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] <instance-id>

Deploy installers from S3 URLs to Windows EC2 instances in stages.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to deploy (dev, staging, prod) [default: dev]
    -a, --auto-approve      Auto-approve changes
    --skip-installer-check  Skip installer connectivity check
    -d, --destroy           Destroy the infrastructure
    -l, --list-installers   List configured installers
    --add-installer         Add a new installer URL interactively

EXAMPLES:
    $0 i-0a0cf65b6a9a9b7d0                    Deploy installers to instance
    $0 -a i-0a0cf65b6a9a9b7d0                 Deploy with auto-approval
    $0 --skip-installer-check i-0a0cf65b6a9a9b7d0  Deploy without checking installer URLs
    $0 -l                                     List configured installers
    $0 --add-installer                        Add new installer interactively

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing_tools=()
    
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

# Function to validate instance
validate_instance() {
    local instance_id="$1"
    
    print_info "Validating instance: $instance_id"
    
    # Verify instance exists and is running
    local instance_state=$(aws ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "not-found")
    
    if [ "$instance_state" = "not-found" ]; then
        print_error "Instance $instance_id not found or access denied"
        exit 1
    elif [ "$instance_state" != "running" ]; then
        print_error "Instance $instance_id is not running (current state: $instance_state)"
        exit 1
    fi
    
    # Check if SSM agent is available
    local ssm_status=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$instance_id" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo "Offline")
    
    if [ "$ssm_status" != "Online" ]; then
        print_error "SSM agent is not online on instance $instance_id (status: $ssm_status)"
        print_error "Please ensure SSM agent is installed and running"
        exit 1
    fi
    
    print_success "Instance validation passed"
    print_success "Instance ID: $instance_id"
    print_success "Instance State: $instance_state"
    print_success "SSM Status: $ssm_status"
}

# Function to list configured installers
list_installers() {
    print_info "Configured Installers:"
    print_info "====================="
    
    if [ ${#INSTALLER_URLS[@]} -eq 0 ]; then
        print_warning "No installers configured"
        print_info "Use --add-installer to add installers interactively"
        return 0
    fi
    
    for i in "${!INSTALLER_URLS[@]}"; do
        local url="${INSTALLER_URLS[$i]}"
        local name="${INSTALLER_NAMES[$i]:-Unnamed}"
        local type="${INSTALLER_TYPES[$i]:-Unknown}"
        
        echo "  [$((i+1))] $name ($type)"
        echo "      URL: $url"
        echo ""
    done
}

# Function to add installer interactively
add_installer() {
    print_info "Adding new installer..."
    
    echo -n "Enter installer name: "
    read -r installer_name
    
    echo -n "Enter S3 URL: "
    read -r installer_url
    
    echo -n "Enter installer type (msi, exe, zip, etc.): "
    read -r installer_type
    
    # Validate URL
    if [[ ! "$installer_url" =~ ^https?:// ]]; then
        print_error "Invalid URL format"
        return 1
    fi
    
    # Add to arrays
    INSTALLER_URLS+=("$installer_url")
    INSTALLER_NAMES+=("$installer_name")
    INSTALLER_TYPES+=("$installer_type")
    
    print_success "Installer added successfully"
    print_info "Name: $installer_name"
    print_info "URL: $installer_url"
    print_info "Type: $installer_type"
    
    # Save to script (this would require modifying the script file)
    print_warning "Note: To persist this installer, you need to manually add it to the script arrays"
}

# Function to validate installer URLs
validate_installer_urls() {
    if [ ${#INSTALLER_URLS[@]} -eq 0 ]; then
        print_warning "No installers configured"
        return 0
    fi
    
    print_info "Validating installer URLs..."
    
    for i in "${!INSTALLER_URLS[@]}"; do
        local url="${INSTALLER_URLS[$i]}"
        local name="${INSTALLER_NAMES[$i]:-Unnamed}"
        
        if [ -z "$url" ]; then
            print_warning "Skipping empty URL for installer: $name"
            continue
        fi
        
        print_info "Checking: $name"
        
        # Test URL accessibility
        if curl -s --head "$url" | head -n 1 | grep -q "200 OK"; then
            print_success "✅ $name - URL accessible"
        else
            print_warning "⚠️ $name - URL might not be accessible"
        fi
    done
}

# Function to create PowerShell installer script
create_powershell_script() {
    local script_path="$SCRIPT_DIR/$POWERSHELL_SCRIPT_NAME"
    
    print_info "Creating PowerShell installer script..."
    
    cat > "$script_path" << 'EOF'
# PowerShell Script for Installer Deployment
# This script downloads and installs software from S3 URLs

param(
    [string[]]$InstallerUrls = @(),
    [string[]]$InstallerNames = @(),
    [string[]]$InstallerTypes = @()
)

# Set up logging
$LogDir = "C:\logs"
if (!(Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force
}

$LogFile = "$LogDir\installer-deployment.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Write-Host $LogEntry
    Add-Content -Path $LogFile -Value $LogEntry
}

function Download-Installer {
    param(
        [string]$Url,
        [string]$Name,
        [string]$Type
    )
    
    Write-Log "Starting download: $Name" "INFO"
    
    try {
        # Create downloads directory
        $DownloadDir = "C:\downloads"
        if (!(Test-Path $DownloadDir)) {
            New-Item -ItemType Directory -Path $DownloadDir -Force
        }
        
        # Extract filename from URL
        $FileName = Split-Path $Url -Leaf
        $FilePath = "$DownloadDir\$FileName"
        
        # Download file
        Write-Log "Downloading $Name from $Url" "INFO"
        Invoke-WebRequest -Uri $Url -OutFile $FilePath -UseBasicParsing
        
        if (Test-Path $FilePath) {
            Write-Log "Download completed: $Name" "SUCCESS"
            return $FilePath
        } else {
            Write-Log "Download failed: $Name" "ERROR"
            return $null
        }
    }
    catch {
        Write-Log "Download error for $Name : $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Install-Software {
    param(
        [string]$FilePath,
        [string]$Name,
        [string]$Type
    )
    
    Write-Log "Starting installation: $Name" "INFO"
    
    try {
        switch ($Type.ToLower()) {
            "msi" {
                Write-Log "Installing MSI: $Name" "INFO"
                $Arguments = "/i `"$FilePath`" /quiet /norestart"
                Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait
            }
            "exe" {
                Write-Log "Installing EXE: $Name" "INFO"
                Start-Process -FilePath $FilePath -ArgumentList "/S" -Wait
            }
            "zip" {
                Write-Log "Extracting ZIP: $Name" "INFO"
                $ExtractDir = "C:\Program Files\$Name"
                Expand-Archive -Path $FilePath -DestinationPath $ExtractDir -Force
            }
            default {
                Write-Log "Unknown installer type: $Type for $Name" "WARNING"
                Write-Log "Attempting to run as executable: $Name" "INFO"
                Start-Process -FilePath $FilePath -Wait
            }
        }
        
        Write-Log "Installation completed: $Name" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Installation error for $Name : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main execution
Write-Log "Starting installer deployment process" "INFO"
Write-Log "Number of installers: $($InstallerUrls.Count)" "INFO"

$SuccessCount = 0
$FailureCount = 0

for ($i = 0; $i -lt $InstallerUrls.Count; $i++) {
    $Url = $InstallerUrls[$i]
    $Name = if ($i -lt $InstallerNames.Count) { $InstallerNames[$i] } else { "Installer $($i+1)" }
    $Type = if ($i -lt $InstallerTypes.Count) { $InstallerTypes[$i] } else { "unknown" }
    
    if ([string]::IsNullOrEmpty($Url)) {
        Write-Log "Skipping empty URL for: $Name" "WARNING"
        continue
    }
    
    Write-Log "Processing installer $($i+1)/$($InstallerUrls.Count): $Name" "INFO"
    
    # Download installer
    $FilePath = Download-Installer -Url $Url -Name $Name -Type $Type
    
    if ($FilePath) {
        # Install software
        if (Install-Software -FilePath $FilePath -Name $Name -Type $Type) {
            $SuccessCount++
            Write-Log "✅ Successfully installed: $Name" "SUCCESS"
        } else {
            $FailureCount++
            Write-Log "❌ Failed to install: $Name" "ERROR"
        }
        
        # Clean up downloaded file
        try {
            Remove-Item $FilePath -Force
            Write-Log "Cleaned up downloaded file: $Name" "INFO"
        }
        catch {
            Write-Log "Failed to clean up file: $Name" "WARNING"
        }
    } else {
        $FailureCount++
        Write-Log "❌ Failed to download: $Name" "ERROR"
    }
}

# Final summary
Write-Log "Installation process completed" "INFO"
Write-Log "Successful installations: $SuccessCount" "SUCCESS"
Write-Log "Failed installations: $FailureCount" "ERROR"

if ($FailureCount -eq 0) {
    Write-Log "All installers deployed successfully!" "SUCCESS"
    exit 0
} else {
    Write-Log "Some installers failed to deploy" "ERROR"
    exit 1
}
EOF

    print_success "PowerShell script created: $script_path"
}

# Function to deploy installers via SSM
deploy_installers() {
    local instance_id="$1"
    
    print_info "Deploying installers to instance: $instance_id"
    
    # Create PowerShell script
    create_powershell_script
    
    # Prepare parameters for PowerShell script
    local urls_json=$(printf '%s\n' "${INSTALLER_URLS[@]}" | jq -R . | jq -s .)
    local names_json=$(printf '%s\n' "${INSTALLER_NAMES[@]}" | jq -R . | jq -s .)
    local types_json=$(printf '%s\n' "${INSTALLER_TYPES[@]}" | jq -R . | jq -s .)
    
    # Base64 encode the PowerShell script
    local base64_script=$(base64 -w 0 "$SCRIPT_DIR/$POWERSHELL_SCRIPT_NAME")
    
    if [ -z "$base64_script" ]; then
        print_error "Failed to base64 encode the PowerShell script"
        exit 1
    fi
    
    print_info "Sending installer deployment command via SSM..."
    
    # Send command via SSM
    local command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters "commands=[\"[System.IO.File]::WriteAllText('C:\\\\$POWERSHELL_SCRIPT_NAME', [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$base64_script'))); Set-ExecutionPolicy RemoteSigned -Force; C:\\\\$POWERSHELL_SCRIPT_NAME -InstallerUrls $urls_json -InstallerNames $names_json -InstallerTypes $types_json\"]" \
        --output text \
        --query 'Command.CommandId')
    
    if [ -z "$command_id" ]; then
        print_error "Failed to send command via SSM"
        exit 1
    fi
    
    print_success "Command ID: $command_id"
    log_message "INFO" "Installer deployment command initiated with ID: $command_id"
    
    # Store command ID for monitoring
    echo "$command_id" > "$SCRIPT_DIR/last_installer_command_id.txt"
    
    print_success "Installer deployment command sent successfully"
    print_info "Use 'monitor_installers' function to check progress"
    
    return "$command_id"
}

# Function to monitor installer deployment progress
monitor_installers() {
    local instance_id="$1"
    local command_id="$2"
    local max_wait=${3:-1800}  # Default 30 minutes
    
    local elapsed=0
    local interval=30
    
    print_info "⏳ Monitoring installer deployment progress..."
    
    while [ $elapsed -lt $max_wait ]; do
        # Check command status
        local status=$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" --query 'Status' --output text 2>/dev/null || echo "not-found")
        
        if [ "$status" = "not-found" ]; then
            print_error "Command not found or access denied"
            return 1
        fi
        
        case "$status" in
            "InProgress")
                if [ $((elapsed % 60)) -eq 0 ]; then
                    print_progress "Installation still in progress... ($((elapsed / 60)) minutes elapsed)"
                fi
                ;;
            "Success")
                print_success "✅ Installer deployment completed successfully!"
                
                # Get command output
                print_info "Installation Summary:"
                aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" --query 'StandardOutputContent' --output text
                
                return 0
                ;;
            "Failed"|"Cancelled"|"TimedOut")
                print_error "Installer deployment failed with status: $status"
                
                # Get error output
                print_error "Error Details:"
                aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" --query 'StandardErrorContent' --output text
                
                return 1
                ;;
            *)
                print_warning "Unknown status: $status"
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_warning "Timeout after $((max_wait / 60)) minutes"
    print_warning "Deployment might still be running. Check manually."
    
    return 1
}

# Function to get instance connection information
get_connection_info() {
    local instance_id="$1"
    
    print_info "Getting instance connection information..."
    
    # Get public IP
    local public_ip=$(aws ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || echo "N/A")
    
    # Get private IP
    local private_ip=$(aws ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo "N/A")
    
    print_success "Instance Connection Information:"
    print_info "Instance ID: $instance_id"
    print_info "Public IP: $public_ip"
    print_info "Private IP: $private_ip"
    
    if [ "$public_ip" != "N/A" ] && [ "$public_ip" != "None" ]; then
        print_info "RDP Connection: $public_ip:3389"
    else
        print_info "RDP Connection: $private_ip:3389"
    fi
}

# Main execution function
main() {
    local instance_id=""
    
    # Initialize log file
    echo "Installer Deployment Log - $(date)" > "$LOG_FILE"
    
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
            --skip-installer-check)
                SKIP_INSTALLER_CHECK=true
                shift
                ;;
            -d|--destroy)
                DESTROY=true
                shift
                ;;
            -l|--list-installers)
                list_installers
                exit 0
                ;;
            --add-installer)
                add_installer
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$instance_id" ]; then
                    instance_id="$1"
                else
                    print_error "Multiple instance IDs provided"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    if [ -z "$instance_id" ]; then
        print_error "Instance ID is required"
        show_usage
        exit 1
    fi
    
    print_info "🚀 Starting staged installer deployment"
    print_info "Environment: $ENVIRONMENT"
    print_info "Instance ID: $instance_id"
    
    # Check prerequisites
    check_prerequisites
    
    # Validate instance
    validate_instance "$instance_id"
    
    # List configured installers
    list_installers
    
    if [ ${#INSTALLER_URLS[@]} -eq 0 ]; then
        print_warning "No installers configured. Use --add-installer to add installers."
        exit 0
    fi
    
    # Validate installer URLs (unless skipped)
    if [[ "$SKIP_INSTALLER_CHECK" != true ]]; then
        validate_installer_urls
    fi
    
    # Deploy installers
    print_info "📦 Stage 1: Deploying installers..."
    local command_id=$(deploy_installers "$instance_id")
    
    # Monitor deployment
    print_info "📦 Stage 2: Monitoring deployment progress..."
    if monitor_installers "$instance_id" "$command_id"; then
        print_success "✅ Installer deployment completed successfully!"
    else
        print_warning "⚠️ Installer deployment may have issues. Check logs."
    fi
    
    # Display connection information
    get_connection_info "$instance_id"
    
    print_success "✅ Deployment process completed!"
    print_info "Check the log file for detailed information: $LOG_FILE"
}

# Execute main function
main "$@"
