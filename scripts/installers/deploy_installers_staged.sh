#!/bin/bash

# S3 Installer Deployment Script for Windows EC2 via SSM
# This script deploys installers from S3 URLs to Windows instances with progress monitoring
# Similar to how NiceDCV is deployed, but for general installers from S3 bucket

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
LOG_FILE="$SCRIPT_DIR/installer_deployment.log"

# Default values
AUTO_APPROVE=false
SKIP_URL_CHECK=false

# S3 Access Point configuration
S3_ACCESS_POINT_ALIAS="your-access-point-alias-s3alias"
S3_ACCESS_POINT_ARN="arn:aws:s3:us-east-1:123456789012:accesspoint/your-access-point-name"
AWS_REGION="us-east-1"

# Array of S3 object keys (you can modify these as needed)
declare -a INSTALLER_KEYS=(
    # Add your S3 object keys here
    # Example: "NiceDCV/Amazon DCV 2024.0 Client/Windows x86_64/Version 2024.0-9431/nice-dcv-client-Release.msi"
    # Example: "CMake/Windows x86_64/Version 4.1.1/cmake-4.1.1-windows-x86_64.msi"
    "CMake/Windows x86_64/Version 4.1.1/cmake-4.1.1-windows-x86_64.msi"
    "Git/Windows x86_64/Version 2.51.0/Git-2.51.0-64-bit.exe"
    "NASM/Windows x86_64/Version 2.16.03/nasm-2.16.03-installer-x64.exe"
    "Python Manager/Windows x86_64/Version 25.0b14/python-manager-25.0b14.msi"
    "Strawberry Perl/Windows x86_64/Version 5.40.2.1/strawberry-perl-5.40.2.1-64bit.msi"
)

# Array of installer URLs (for backward compatibility and validation)
declare -a INSTALLER_URLS=(
    # These will be constructed from INSTALLER_KEYS and S3_ACCESS_POINT_ALIAS
    # Example: "https://your-access-point-alias-s3alias.s3.us-east-1.amazonaws.com/CMake/Windows%20x86_64/Version%204.1.1/cmake-4.1.1-windows-x86_64.msi"
)

# Array of installer names (corresponding to INSTALLER_KEYS array)
declare -a INSTALLER_NAMES=(
    "CMake"
    "Git for Windows"
    "NASM Assembler"
    "Python Manager"
    "Strawberry Perl"
)

# Array of installer types (corresponding to INSTALLER_KEYS array)
declare -a INSTALLER_TYPES=(
    "msi"
    "exe"
    "exe"
    "msi"
    "msi"
)

# Array of installer arguments for silent installation
declare -a INSTALLER_ARGS=(
    "/quiet /norestart"                    # CMake - MSI standard
    "/VERYSILENT /NORESTART"                # Git - Inno Setup
    "/S"                                    # NASM - NSIS installer
    "/quiet /norestart"                     # Python Manager - MSI standard
    "/quiet /norestart"                     # Strawberry Perl - MSI standard
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

Deploy installers from S3 URLs to Windows EC2 instances via SSM.

OPTIONS:
    -h, --help              Show this help message
    -a, --auto-approve      Auto-approve deployment
    --skip-url-check        Skip S3 URL validation
    -l, --list-installers   List configured installers
    --add-installer         Add a new installer URL interactively
    --check-status          Check installation status

REQUIRED:
    instance-id             EC2 instance ID to deploy installers to

EXAMPLES:
    $0 i-0a0cf65b6a9a9b7d0                    Deploy installers to instance
    $0 -a i-0a0cf65b6a9a9b7d0                 Deploy with auto-approval
    $0 --skip-url-check i-0a0cf65b6a9a9b7d0   Deploy without checking S3 URLs
    $0 -l                                      List configured installers
    $0 --check-status i-0a0cf65b6a9a9b7d0     Check installation status

NOTES:
    - Instance must have SSM agent installed and running
    - Instance must have appropriate IAM role for SSM
    - S3 URLs must be publicly accessible or instance must have S3 access

EOF
}

# Function to build URLs from S3 keys
build_installer_urls() {
    INSTALLER_URLS=()
    for key in "${INSTALLER_KEYS[@]}"; do
        if [ -n "$key" ] && [ -n "$S3_ACCESS_POINT_ALIAS" ]; then
            # URL encode the key for the URL
            local encoded_key=$(echo "$key" | sed 's/ /%20/g')
            local url="https://${S3_ACCESS_POINT_ALIAS}.s3.${AWS_REGION}.amazonaws.com/${encoded_key}"
            INSTALLER_URLS+=("$url")
        fi
    done
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
    
    # Check curl for URL validation
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
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
    local instance_state=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "not-found")
    
    if [ "$instance_state" = "not-found" ]; then
        print_error "Instance $instance_id not found or access denied"
        exit 1
    elif [ "$instance_state" != "running" ]; then
        print_error "Instance $instance_id is not running (current state: $instance_state)"
        exit 1
    fi
    
    # Check if SSM agent is available
    local ssm_status=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$instance_id" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "Offline")
    
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
    
    if [ ${#INSTALLER_KEYS[@]} -eq 0 ]; then
        print_warning "No installers configured"
        return 0
    fi
    
    for i in "${!INSTALLER_KEYS[@]}"; do
        local key="${INSTALLER_KEYS[$i]}"
        local name="${INSTALLER_NAMES[$i]:-Unnamed}"
        local type="${INSTALLER_TYPES[$i]:-Unknown}"
        local args="${INSTALLER_ARGS[$i]:-Default}"
        
        echo ""
        echo "  [$((i+1))] $name"
        echo "      Type: $type"
        echo "      Args: $args"
        echo "      S3 Key: $key"
    done
    echo ""
}

# Function to add installer interactively
add_installer() {
    print_info "Adding new installer..."
    
    echo -n "Enter installer name: "
    read -r installer_name
    
    echo -n "Enter S3 object key: "
    read -r installer_key
    
    echo -n "Enter installer type (msi, exe, zip, etc.): "
    read -r installer_type
    
    echo -n "Enter silent install arguments (e.g., /quiet for MSI): "
    read -r installer_args
    
    # Validate key (basic check for non-empty)
    if [ -z "$installer_key" ]; then
        print_error "S3 object key cannot be empty"
        return 1
    fi
    
    # Add to arrays
    INSTALLER_KEYS+=("$installer_key")
    INSTALLER_NAMES+=("$installer_name")
    INSTALLER_TYPES+=("$installer_type")
    INSTALLER_ARGS+=("$installer_args")
    
    print_success "Installer added successfully"
    print_info "Name: $installer_name"
    print_info "S3 Key: $installer_key"
    print_info "Type: $installer_type"
    print_info "Args: $installer_args"
    
    print_warning "Note: To persist this installer, manually add it to the script arrays"
}

# Function to validate S3 object keys
validate_s3_keys() {
    if [ ${#INSTALLER_KEYS[@]} -eq 0 ]; then
        print_warning "No installers configured"
        return 0
    fi
    
    print_info "Validating S3 object keys..."
    
    local failed_count=0
    for i in "${!INSTALLER_KEYS[@]}"; do
        local key="${INSTALLER_KEYS[$i]}"
        local name="${INSTALLER_NAMES[$i]:-Unnamed}"
        
        if [ -z "$key" ]; then
            print_warning "Skipping empty key for installer: $name"
            continue
        fi
        
        print_progress "Checking: $name"
        
        # Test S3 object accessibility using AWS CLI
        if aws s3api head-object --bucket "$S3_ACCESS_POINT_ARN" --key "$key" --region "$AWS_REGION" &>/dev/null; then
            print_success "  ✅ $name - S3 object accessible"
        else
            print_error "  ❌ $name - S3 object not accessible"
            ((failed_count++))
        fi
    done
    
    if [ $failed_count -gt 0 ]; then
        print_warning "$failed_count URL(s) failed validation"
        if [[ "$SKIP_URL_CHECK" != true ]]; then
            print_error "Use --skip-url-check to bypass validation"
            return 1
        fi
    fi
    
    return 0
}

# Function to create PowerShell installer script
create_powershell_script() {
    local script_path="/tmp/$POWERSHELL_SCRIPT_NAME"
    
    print_info "Creating PowerShell installer script..."
    
    cat > "$script_path" << 'EOF'
# PowerShell Script for S3 Installer Deployment
# This script downloads and installs software from S3 URLs

param(
    [string[]]$InstallerUrls = @(),
    [string[]]$InstallerNames = @(),
    [string[]]$InstallerTypes = @(),
    [string[]]$InstallerArgs = @(),
    [string[]]$InstallerKeys = @(),
    [string]$S3AccessPointArn = "",
    [string]$AwsRegion = "us-east-1"
)

# Set up logging
$LogDir = "C:\logs"
if (!(Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = "$LogDir\installer-deployment.log"
$Timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$SessionLogFile = "$LogDir\installer-deployment-$Timestamp.log"

# Set up download directory
$DownloadDir = "C:\temp\installers"
if (!(Test-Path $DownloadDir)) {
    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
}

# Start transcript
Start-Transcript -Path $SessionLogFile -Append

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
        [string]$S3Key,
        [string]$Name
    )
    
    Write-Log "Downloading: $Name" "INFO"
    
    try {
        # Extract filename from S3 key or URL
        $FileName = if ($S3Key) { Split-Path $S3Key -Leaf } else { Split-Path $Url -Leaf }
        $FilePath = "$DownloadDir\$FileName"
        
        Write-Log "  S3 Key: $S3Key" "INFO"
        Write-Log "  URL: $Url" "INFO"
        Write-Log "  Destination: $FilePath" "INFO"
        
        # Download file from S3 using AWS CLI with access point
        if ($S3Key -and $S3AccessPointArn) {
            $awsCommand = "aws s3api get-object --bucket `"$S3AccessPointArn`" --key `"$S3Key`" `"$FilePath`" --region `"$AwsRegion`""
            Write-Log "  Executing: $awsCommand" "DEBUG"
            $result = Invoke-Expression $awsCommand
        } else {
            # Fallback to URL download
            Write-Log "  Downloading from URL: $Url" "INFO"
            Invoke-WebRequest -Uri $Url -OutFile $FilePath -UseBasicParsing
        }
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $FilePath)) {
            $FileSize = (Get-Item $FilePath).Length / 1MB
            Write-Log "  Download completed: $Name (${FileSize}MB)" "SUCCESS"
            return $FilePath
        } else {
            Write-Log "  Download failed: $Name (Exit code: $LASTEXITCODE)" "ERROR"
            return $null
        }
    }
    catch {
        Write-Log "  Download error for $Name : $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Install-Software {
    param(
        [string]$FilePath,
        [string]$Name,
        [string]$Type,
        [string]$Args
    )
    
    Write-Log "Installing: $Name" "INFO"
    Write-Log "  File: $FilePath" "INFO"
    Write-Log "  Type: $Type" "INFO"
    Write-Log "  Args: $Args" "INFO"
    
    try {
        $Process = $null
        
        switch ($Type.ToLower()) {
            "msi" {
                Write-Log "  Running MSI installer" "INFO"
                if ([string]::IsNullOrEmpty($Args)) {
                    $Args = "/quiet /norestart"
                }
                $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$FilePath`" $Args" -Wait -PassThru
            }
            "exe" {
                Write-Log "  Running EXE installer" "INFO"
                if ([string]::IsNullOrEmpty($Args)) {
                    $Args = "/S"
                }
                $Process = Start-Process -FilePath $FilePath -ArgumentList $Args -Wait -PassThru
            }
            "zip" {
                Write-Log "  Extracting ZIP archive" "INFO"
                $ExtractDir = "C:\Program Files\$Name"
                Expand-Archive -Path $FilePath -DestinationPath $ExtractDir -Force
                Write-Log "  Extracted to: $ExtractDir" "INFO"
                return $true
            }
            default {
                Write-Log "  Unknown installer type: $Type" "WARNING"
                Write-Log "  Attempting to run as executable" "INFO"
                $Process = Start-Process -FilePath $FilePath -Wait -PassThru
            }
        }
        
        if ($Process) {
            $ExitCode = $Process.ExitCode
            Write-Log "  Installation exit code: $ExitCode" "INFO"
            
            if ($ExitCode -eq 0 -or $ExitCode -eq 3010) {
                Write-Log "  Installation completed: $Name" "SUCCESS"
                return $true
            } else {
                Write-Log "  Installation failed with exit code: $ExitCode" "ERROR"
                return $false
            }
        }
        
        return $true
    }
    catch {
        Write-Log "  Installation error for $Name : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main execution
Write-Log "========================================" "INFO"
Write-Log "Starting S3 Installer Deployment Process" "INFO"
Write-Log "========================================" "INFO"
Write-Log "Number of installers: $($InstallerUrls.Count)" "INFO"

$SuccessCount = 0
$FailureCount = 0
$SkippedCount = 0

# Create progress marker file
$ProgressFile = "$LogDir\installer-deployment-progress.txt"
"STARTED" | Out-File -FilePath $ProgressFile -Force

for ($i = 0; $i -lt $InstallerUrls.Count; $i++) {
    $Url = $InstallerUrls[$i]
    $S3Key = if ($i -lt $InstallerKeys.Count) { $InstallerKeys[$i] } else { "" }
    $Name = if ($i -lt $InstallerNames.Count) { $InstallerNames[$i] } else { "Installer $($i+1)" }
    $Type = if ($i -lt $InstallerTypes.Count) { $InstallerTypes[$i] } else { "unknown" }
    $InstallArgs = if ($i -lt $InstallerArgs.Count) { $InstallerArgs[$i] } else { "" }
    
    if ([string]::IsNullOrEmpty($Url) -and [string]::IsNullOrEmpty($S3Key)) {
        Write-Log "Skipping empty URL and S3 key for: $Name" "WARNING"
        $SkippedCount++
        continue
    }
    
    Write-Log "" "INFO"
    Write-Log "Processing installer $($i+1)/$($InstallerUrls.Count): $Name" "INFO"
    Write-Log "----------------------------------------" "INFO"
    
    # Update progress
    "INSTALLING: $Name ($($i+1)/$($InstallerUrls.Count))" | Out-File -FilePath $ProgressFile -Force
    
    # Download installer
    $FilePath = Download-Installer -Url $Url -S3Key $S3Key -Name $Name
    
    if ($FilePath) {
        # Install software
        if (Install-Software -FilePath $FilePath -Name $Name -Type $Type -Args $InstallArgs) {
            $SuccessCount++
            Write-Log "✅ Successfully installed: $Name" "SUCCESS"
        } else {
            $FailureCount++
            Write-Log "❌ Failed to install: $Name" "ERROR"
        }
        
        # Clean up downloaded file
        try {
            Remove-Item $FilePath -Force -ErrorAction SilentlyContinue
            Write-Log "  Cleaned up installer file" "INFO"
        }
        catch {
            Write-Log "  Failed to clean up file: $($_.Exception.Message)" "WARNING"
        }
    } else {
        $FailureCount++
        Write-Log "❌ Failed to download: $Name" "ERROR"
    }
}

# Final summary
Write-Log "" "INFO"
Write-Log "========================================" "INFO"
Write-Log "Installation Process Completed" "INFO"
Write-Log "========================================" "INFO"
Write-Log "Successful installations: $SuccessCount" "SUCCESS"
Write-Log "Failed installations: $FailureCount" $(if ($FailureCount -gt 0) { "ERROR" } else { "INFO" })
Write-Log "Skipped installations: $SkippedCount" $(if ($SkippedCount -gt 0) { "WARNING" } else { "INFO" })

# Update progress marker
if ($FailureCount -eq 0) {
    "COMPLETED: All installers deployed successfully!" | Out-File -FilePath $ProgressFile -Force
    Write-Log "All installers deployed successfully!" "SUCCESS"
    Stop-Transcript
    exit 0
} else {
    "COMPLETED_WITH_ERRORS: $FailureCount installations failed" | Out-File -FilePath $ProgressFile -Force
    Write-Log "Some installers failed to deploy" "ERROR"
    Stop-Transcript
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
    
    # Build URLs from S3 keys
    build_installer_urls
    
    # Convert arrays to JSON for PowerShell parameters
    local urls_json=$(printf '%s\n' "${INSTALLER_URLS[@]}" | jq -R . | jq -s -c .)
    local keys_json=$(printf '%s\n' "${INSTALLER_KEYS[@]}" | jq -R . | jq -s -c .)
    local names_json=$(printf '%s\n' "${INSTALLER_NAMES[@]}" | jq -R . | jq -s -c .)
    local types_json=$(printf '%s\n' "${INSTALLER_TYPES[@]}" | jq -R . | jq -s -c .)
    local args_json=$(printf '%s\n' "${INSTALLER_ARGS[@]}" | jq -R . | jq -s -c .)
    
    # Base64 encode the PowerShell script
    local base64_script=$(base64 -w 0 "/tmp/$POWERSHELL_SCRIPT_NAME")
    
    if [ -z "$base64_script" ]; then
        print_error "Failed to base64 encode the PowerShell script"
        exit 1
    fi
    
    print_info "Sending installer deployment command via SSM..."
    
    # Build the PowerShell command
    local ps_command="[System.IO.File]::WriteAllText('C:\\temp\\$POWERSHELL_SCRIPT_NAME', [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$base64_script'))); "
    ps_command+="Set-ExecutionPolicy RemoteSigned -Force; "
    ps_command+="C:\\temp\\$POWERSHELL_SCRIPT_NAME "
    ps_command+="-InstallerUrls $urls_json "
    ps_command+="-InstallerKeys $keys_json "
    ps_command+="-InstallerNames $names_json "
    ps_command+="-InstallerTypes $types_json "
    ps_command+="-InstallerArgs $args_json "
    ps_command+="-S3AccessPointArn $S3_ACCESS_POINT_ARN "
    ps_command+="-AwsRegion $AWS_REGION"
    
    # Send command via SSM
    local command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters "commands=[\"$ps_command\"]" \
        --timeout-seconds 3600 \
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
    print_info "Monitoring installation progress..."
    
    # Monitor the deployment
    monitor_deployment "$instance_id" "$command_id"
}

# Function to monitor deployment progress
monitor_deployment() {
    local instance_id="$1"
    local command_id="$2"
    local max_wait=${3:-3600}  # Default 60 minutes
    
    local elapsed=0
    local interval=10
    local last_status=""
    
    print_info "⏳ Monitoring installer deployment (timeout: $((max_wait/60)) minutes)..."
    
    while [ $elapsed -lt $max_wait ]; do
        # Check command status
        local status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --query 'Status' \
            --output text 2>/dev/null || echo "Unknown")
        
        # Only print if status changed
        if [ "$status" != "$last_status" ]; then
            print_progress "Status: $status"
            last_status="$status"
        fi
        
        case "$status" in
            "Success")
                print_success "✅ Installer deployment completed successfully!"
                
                # Get command output
                print_info "Installation Summary:"
                echo "----------------------------------------"
                aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --query 'StandardOutputContent' \
                    --output text | tail -50
                echo "----------------------------------------"
                
                return 0
                ;;
            "Failed"|"Cancelled"|"TimedOut")
                print_error "❌ Installer deployment failed with status: $status"
                
                # Get error output
                print_error "Error Details:"
                echo "----------------------------------------"
                aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --query 'StandardErrorContent' \
                    --output text
                echo "----------------------------------------"
                
                return 1
                ;;
            "InProgress"|"Pending"|"Delayed")
                # Still running, continue monitoring
                if [ $((elapsed % 60)) -eq 0 ] && [ $elapsed -gt 0 ]; then
                    print_info "Still installing... ($((elapsed/60)) minutes elapsed)"
                fi
                ;;
            *)
                if [ $((elapsed % 30)) -eq 0 ]; then
                    print_warning "Unknown status: $status"
                fi
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_warning "⏱️ Timeout after $((max_wait/60)) minutes"
    print_warning "Installation might still be running. Check manually with command ID: $command_id"
    
    return 1
}

# Function to check installation status
check_installation_status() {
    local instance_id="$1"
    
    print_info "Checking installation status on instance: $instance_id"
    
    # Check for progress file
    local check_command=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=["Get-Content C:\\logs\\installer-deployment-progress.txt -ErrorAction SilentlyContinue"]' \
        --output text \
        --query 'Command.CommandId')
    
    if [ -n "$check_command" ]; then
        sleep 5
        local progress=$(aws ssm get-command-invocation \
            --command-id "$check_command" \
            --instance-id "$instance_id" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "Unknown")
        
        print_info "Installation Progress: $progress"
    fi
    
    # Check recent logs
    local log_command=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=["Get-Content C:\\logs\\installer-deployment.log -Tail 20 -ErrorAction SilentlyContinue"]' \
        --output text \
        --query 'Command.CommandId')
    
    if [ -n "$log_command" ]; then
        sleep 5
        print_info "Recent Installation Logs:"
        echo "----------------------------------------"
        aws ssm get-command-invocation \
            --command-id "$log_command" \
            --instance-id "$instance_id" \
            --query 'StandardOutputContent' \
            --output text
        echo "----------------------------------------"
    fi
}

# Main execution function
main() {
    local instance_id=""
    local action=""
    
    # Initialize log file
    echo "S3 Installer Deployment Log - $(date)" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -a|--auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --skip-url-check)
                SKIP_URL_CHECK=true
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
            --check-status)
                action="check-status"
                shift
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
    
    print_info "🚀 Starting S3 Installer Deployment"
    print_info "Instance ID: $instance_id"
    print_info "Number of installers: ${#INSTALLER_URLS[@]}"
    
    # Check prerequisites
    check_prerequisites
    
    # Validate instance
    validate_instance "$instance_id"
    
    # Handle different actions
    if [ "$action" = "check-status" ]; then
        check_installation_status "$instance_id"
        exit 0
    fi
    
    # Build URLs from S3 keys if not already built
    if [ ${#INSTALLER_URLS[@]} -eq 0 ] && [ ${#INSTALLER_KEYS[@]} -gt 0 ]; then
        build_installer_urls
    fi
    
    # List configured installers
    list_installers
    
    if [ ${#INSTALLER_URLS[@]} -eq 0 ]; then
        print_warning "No installers configured. Use --add-installer to add installers."
        exit 0
    fi
    
    # Validate S3 keys and URLs (unless skipped)
    if [[ "$SKIP_URL_CHECK" != true ]]; then
        if ! validate_s3_keys; then
            print_error "S3 key validation failed. Use --skip-url-check to bypass."
            exit 1
        fi
    fi
    
    # Confirm deployment
    if [[ "$AUTO_APPROVE" != true ]]; then
        echo ""
        print_warning "About to deploy ${#INSTALLER_URLS[@]} installers to instance $instance_id"
        echo -n "Do you want to continue? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Deploy installers
    print_info "📦 Starting installer deployment..."
    deploy_installers "$instance_id"
    
    print_success "✅ Deployment process completed!"
    print_info "Check the log file for details: $LOG_FILE"
    print_info "Check installation logs on instance: C:\\logs\\installer-deployment.log"
}

# Execute main function
main "$@"