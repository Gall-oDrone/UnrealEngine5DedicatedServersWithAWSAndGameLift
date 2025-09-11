#!/bin/bash

# Staged Repository Deployment Script for Windows EC2 via SSM
# This script clones repositories to Windows instances in stages with progress monitoring
# Follows the same logic as deploy_installers_staged.sh but for Git repositories

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
LOG_FILE="$SCRIPT_DIR/repo_deployment.log"

# Default values
ENVIRONMENT="dev"
AUTO_APPROVE=false
SKIP_REPO_CHECK=false
DESTROY=false

# Array of repository URLs (you can modify these as needed)
declare -a REPO_URLS=(
    # Add your repository URLs here
    # Example: "https://github.com/username/repository.git"
    # Example: "https://github.com/EpicGames/UnrealEngine.git"
    https://github.com/amazon-gamelift/amazon-gamelift-plugin-unreal.git
)

# Array of repository names (corresponding to REPO_URLS array)
declare -a REPO_NAMES=(
    # Add descriptive names for your repositories
    # Example: "My Project"
    # Example: "Unreal Engine"
    "Amazon GameLift Plugin for Unreal Engine"
)

# Array of repository branches (corresponding to REPO_URLS array)
declare -a REPO_BRANCHES=(
    # Add branch names for your repositories
    # Example: "main"
    # Example: "release"
    "main"
)

# Array of destination directories (corresponding to REPO_URLS array)
declare -a REPO_DESTINATIONS=(
    # Add destination directories for your repositories
    # Example: "C:\Projects\MyProject"
    # Example: "C:\UnrealEngine"
    "D:\UnrealEngine\AmazonGameLiftPlugin"
)

# PowerShell script for repository cloning
POWERSHELL_SCRIPT_NAME="repo_clone.ps1"

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

Clone repositories to Windows EC2 instances in stages.

OPTIONS:
    -h, --help              Show this help message
    -e, --environment       Environment to deploy (dev, staging, prod) [default: dev]
    -a, --auto-approve      Auto-approve changes
    --skip-repo-check       Skip repository connectivity check
    -d, --destroy           Destroy the infrastructure
    -l, --list-repos        List configured repositories
    --add-repo              Add a new repository URL interactively
    --update-repos          Update existing repositories
    --pull-repos            Pull latest changes for existing repositories

EXAMPLES:
    $0 i-0a0cf65b6a9a9b7d0                    Clone repositories to instance
    $0 -a i-0a0cf65b6a9a9b7d0                 Clone with auto-approval
    $0 --skip-repo-check i-0a0cf65b6a9a9b7d0  Clone without checking repository URLs
    $0 -l                                     List configured repositories
    $0 --add-repo                             Add new repository interactively
    $0 --update-repos i-0a0cf65b6a9a9b7d0     Update existing repositories
    $0 --pull-repos i-0a0cf65b6a9a9b7d0       Pull latest changes

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

# Function to list configured repositories
list_repos() {
    print_info "Configured Repositories:"
    print_info "======================="
    
    if [ ${#REPO_URLS[@]} -eq 0 ]; then
        print_warning "No repositories configured"
        print_info "Use --add-repo to add repositories interactively"
        return 0
    fi
    
    for i in "${!REPO_URLS[@]}"; do
        local url="${REPO_URLS[$i]}"
        local name="${REPO_NAMES[$i]:-Unnamed}"
        local branch="${REPO_BRANCHES[$i]:-main}"
        local destination="${REPO_DESTINATIONS[$i]:-C:\Repos\$name}"
        
        echo "  [$((i+1))] $name"
        echo "      URL: $url"
        echo "      Branch: $branch"
        echo "      Destination: $destination"
        echo ""
    done
}

# Function to add repository interactively
add_repo() {
    print_info "Adding new repository..."
    
    echo -n "Enter repository name: "
    read -r repo_name
    
    echo -n "Enter repository URL: "
    read -r repo_url
    
    echo -n "Enter branch name [main]: "
    read -r repo_branch
    repo_branch=${repo_branch:-main}
    
    echo -n "Enter destination directory [C:\\Repos\\$repo_name]: "
    read -r repo_destination
    repo_destination=${repo_destination:-"C:\\Repos\\$repo_name"}
    
    # Validate URL
    if [[ ! "$repo_url" =~ ^https?://.*\.git$ ]]; then
        print_warning "URL doesn't end with .git, but continuing..."
    fi
    
    # Add to arrays
    REPO_URLS+=("$repo_url")
    REPO_NAMES+=("$repo_name")
    REPO_BRANCHES+=("$repo_branch")
    REPO_DESTINATIONS+=("$repo_destination")
    
    print_success "Repository added successfully"
    print_info "Name: $repo_name"
    print_info "URL: $repo_url"
    print_info "Branch: $repo_branch"
    print_info "Destination: $repo_destination"
    
    # Save to script (this would require modifying the script file)
    print_warning "Note: To persist this repository, you need to manually add it to the script arrays"
}

# Function to validate repository URLs
validate_repo_urls() {
    if [ ${#REPO_URLS[@]} -eq 0 ]; then
        print_warning "No repositories configured"
        return 0
    fi
    
    print_info "Validating repository URLs..."
    
    for i in "${!REPO_URLS[@]}"; do
        local url="${REPO_URLS[$i]}"
        local name="${REPO_NAMES[$i]:-Unnamed}"
        
        if [ -z "$url" ]; then
            print_warning "Skipping empty URL for repository: $name"
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

# Function to create PowerShell repository cloning script
create_powershell_script() {
    local script_path="$SCRIPT_DIR/$POWERSHELL_SCRIPT_NAME"
    local operation="$1"  # clone, update, pull
    
    print_info "Creating PowerShell repository script for operation: $operation"
    
    cat > "$script_path" << EOF
# PowerShell Script for Repository Operations
# This script clones, updates, or pulls repositories

param(
    [string[]]\$RepoUrls = @(),
    [string[]]\$RepoNames = @(),
    [string[]]\$RepoBranches = @(),
    [string[]]\$RepoDestinations = @(),
    [string]\$Operation = "clone"
)

# Set up logging
\$LogDir = "C:\\logs"
if (!(Test-Path \$LogDir)) {
    New-Item -ItemType Directory -Path \$LogDir -Force
}

\$LogFile = "\$LogDir\\repo-deployment.log"

# Set up download directory
\$DCVDownloadDir = "C:\\downloads"
if (!(Test-Path \$DCVDownloadDir)) {
    New-Item -ItemType Directory -Path \$DCVDownloadDir -Force
}

function Write-Log {
    param([string]\$Message, [string]\$Level = "INFO")
    \$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    \$LogEntry = "[\$Timestamp] [\$Level] \$Message"
    Write-Host \$LogEntry
    Add-Content -Path \$LogFile -Value \$LogEntry
}

function Test-GitInstalled {
    try {
        \$gitVersion = git --version 2>\$null
        if (\$gitVersion) {
            Write-Log "Git is installed: \$gitVersion" "INFO"
            return \$true
        }
    }
    catch {
        Write-Log "Git is not installed" "ERROR"
        return \$false
    }
    return \$false
}

function Install-Git {
    Write-Log "Installing Git..." "INFO"
    try {
        # Download Git for Windows
        \$gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe"
        \$gitInstaller = "\$DCVDownloadDir\\Git-installer.exe"
        
        Write-Log "Downloading Git installer..." "INFO"
        Invoke-WebRequest -Uri \$gitUrl -OutFile \$gitInstaller -UseBasicParsing
        
        Write-Log "Installing Git..." "INFO"
        Start-Process -FilePath \$gitInstaller -ArgumentList "/VERYSILENT", "/NORESTART" -Wait
        
        # Add Git to PATH
        \$env:PATH += ";C:\\Program Files\\Git\\bin"
        \$env:PATH += ";C:\\Program Files\\Git\\cmd"
        
        Write-Log "Git installation completed" "SUCCESS"
        return \$true
    }
    catch {
        Write-Log "Failed to install Git: \$(\$_.Exception.Message)" "ERROR"
        return \$false
    }
}

function Clone-Repository {
    param(
        [string]\$Url,
        [string]\$Name,
        [string]\$Branch,
        [string]\$Destination
    )
    
    Write-Log "Starting clone: \$Name" "INFO"
    
    try {
        # Create parent directory if it doesn't exist
        \$ParentDir = Split-Path \$Destination -Parent
        if (!(Test-Path \$ParentDir)) {
            New-Item -ItemType Directory -Path \$ParentDir -Force
            Write-Log "Created directory: \$ParentDir" "INFO"
        }
        
        # Check if repository already exists
        if (Test-Path \$Destination) {
            Write-Log "Repository already exists: \$Name at \$Destination" "WARNING"
            return \$true
        }
        
        # Clone repository
        Write-Log "Cloning \$Name from \$Url to \$Destination" "INFO"
        git clone --branch \$Branch \$Url \$Destination
        
        if (Test-Path \$Destination) {
            Write-Log "Clone completed: \$Name" "SUCCESS"
            return \$true
        } else {
            Write-Log "Clone failed: \$Name" "ERROR"
            return \$false
        }
    }
    catch {
        Write-Log "Clone error for \$Name : \$(\$_.Exception.Message)" "ERROR"
        return \$false
    }
}

function Update-Repository {
    param(
        [string]\$Url,
        [string]\$Name,
        [string]\$Branch,
        [string]\$Destination
    )
    
    Write-Log "Starting update: \$Name" "INFO"
    
    try {
        if (!(Test-Path \$Destination)) {
            Write-Log "Repository not found: \$Name at \$Destination" "WARNING"
            return Clone-Repository -Url \$Url -Name \$Name -Branch \$Branch -Destination \$Destination
        }
        
        # Change to repository directory
        Push-Location \$Destination
        
        # Fetch latest changes
        Write-Log "Fetching latest changes for \$Name" "INFO"
        git fetch origin
        
        # Checkout specified branch
        Write-Log "Checking out branch \$Branch for \$Name" "INFO"
        git checkout \$Branch
        
        # Pull latest changes
        Write-Log "Pulling latest changes for \$Name" "INFO"
        git pull origin \$Branch
        
        Pop-Location
        
        Write-Log "Update completed: \$Name" "SUCCESS"
        return \$true
    }
    catch {
        Write-Log "Update error for \$Name : \$(\$_.Exception.Message)" "ERROR"
        Pop-Location
        return \$false
    }
}

function Pull-Repository {
    param(
        [string]\$Url,
        [string]\$Name,
        [string]\$Branch,
        [string]\$Destination
    )
    
    Write-Log "Starting pull: \$Name" "INFO"
    
    try {
        if (!(Test-Path \$Destination)) {
            Write-Log "Repository not found: \$Name at \$Destination" "WARNING"
            return \$false
        }
        
        # Change to repository directory
        Push-Location \$Destination
        
        # Pull latest changes
        Write-Log "Pulling latest changes for \$Name" "INFO"
        git pull origin \$Branch
        
        Pop-Location
        
        Write-Log "Pull completed: \$Name" "SUCCESS"
        return \$true
    }
    catch {
        Write-Log "Pull error for \$Name : \$(\$_.Exception.Message)" "ERROR"
        Pop-Location
        return \$false
    }
}

# Main execution
Write-Log "Starting repository \$Operation process" "INFO"
Write-Log "Number of repositories: \$(\$RepoUrls.Count)" "INFO"

# Check if Git is installed
if (!(Test-GitInstalled)) {
    Write-Log "Git not found, attempting to install..." "WARNING"
    if (!(Install-Git)) {
        Write-Log "Failed to install Git, aborting" "ERROR"
        exit 1
    }
}

\$SuccessCount = 0
\$FailureCount = 0

for (\$i = 0; \$i -lt \$RepoUrls.Count; \$i++) {
    \$Url = \$RepoUrls[\$i]
    \$Name = if (\$i -lt \$RepoNames.Count) { \$RepoNames[\$i] } else { "Repository \$(\$i+1)" }
    \$Branch = if (\$i -lt \$RepoBranches.Count) { \$RepoBranches[\$i] } else { "main" }
    \$Destination = if (\$i -lt \$RepoDestinations.Count) { \$RepoDestinations[\$i] } else { "C:\\Repos\\\$Name" }
    
    if ([string]::IsNullOrEmpty(\$Url)) {
        Write-Log "Skipping empty URL for: \$Name" "WARNING"
        continue
    }
    
    Write-Log "Processing repository \$(\$i+1)/\$(\$RepoUrls.Count): \$Name" "INFO"
    
    # Perform operation based on parameter
    \$success = \$false
    switch (\$Operation.ToLower()) {
        "clone" {
            \$success = Clone-Repository -Url \$Url -Name \$Name -Branch \$Branch -Destination \$Destination
        }
        "update" {
            \$success = Update-Repository -Url \$Url -Name \$Name -Branch \$Branch -Destination \$Destination
        }
        "pull" {
            \$success = Pull-Repository -Url \$Url -Name \$Name -Branch \$Branch -Destination \$Destination
        }
        default {
            Write-Log "Unknown operation: \$Operation" "ERROR"
            \$success = \$false
        }
    }
    
    if (\$success) {
        \$SuccessCount++
        Write-Log "✅ Successfully processed: \$Name" "SUCCESS"
    } else {
        \$FailureCount++
        Write-Log "❌ Failed to process: \$Name" "ERROR"
    }
}

# Final summary
Write-Log "Repository \$Operation process completed" "INFO"
Write-Log "Successful operations: \$SuccessCount" "SUCCESS"
Write-Log "Failed operations: \$FailureCount" "ERROR"

if (\$FailureCount -eq 0) {
    Write-Log "All repositories processed successfully!" "SUCCESS"
    exit 0
} else {
    Write-Log "Some repositories failed to process" "ERROR"
    exit 1
}
EOF

    print_success "PowerShell script created: $script_path"
}

# Function to deploy repositories via SSM
deploy_repos() {
    local instance_id="$1"
    local operation="$2"  # clone, update, pull
    
    print_info "Deploying repositories to instance: $instance_id (operation: $operation)"
    
    # Create PowerShell script
    create_powershell_script "$operation"
    
    # Prepare parameters for PowerShell script
    local urls_json=$(printf '%s\n' "${REPO_URLS[@]}" | jq -R . | jq -s .)
    local names_json=$(printf '%s\n' "${REPO_NAMES[@]}" | jq -R . | jq -s .)
    local branches_json=$(printf '%s\n' "${REPO_BRANCHES[@]}" | jq -R . | jq -s .)
    local destinations_json=$(printf '%s\n' "${REPO_DESTINATIONS[@]}" | jq -R . | jq -s .)
    
    # Base64 encode the PowerShell script
    local base64_script=$(base64 -w 0 "$SCRIPT_DIR/$POWERSHELL_SCRIPT_NAME")
    
    if [ -z "$base64_script" ]; then
        print_error "Failed to base64 encode the PowerShell script"
        exit 1
    fi
    
    print_info "Sending repository $operation command via SSM..."
    
    # Send command via SSM
    local command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters "commands=[\"[System.IO.File]::WriteAllText('C:\\\\$POWERSHELL_SCRIPT_NAME', [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$base64_script'))); Set-ExecutionPolicy RemoteSigned -Force; C:\\\\$POWERSHELL_SCRIPT_NAME -RepoUrls $urls_json -RepoNames $names_json -RepoBranches $branches_json -RepoDestinations $destinations_json -Operation $operation\"]" \
        --output text \
        --query 'Command.CommandId')
    
    if [ -z "$command_id" ]; then
        print_error "Failed to send command via SSM"
        exit 1
    fi
    
    print_success "Command ID: $command_id"
    log_message "INFO" "Repository $operation command initiated with ID: $command_id"
    
    # Store command ID for monitoring
    echo "$command_id" > "$SCRIPT_DIR/last_repo_command_id.txt"
    
    print_success "Repository $operation command sent successfully"
    print_info "Use 'monitor_repos' function to check progress"
    
    return "$command_id"
}

# Function to monitor repository operations progress
monitor_repos() {
    local instance_id="$1"
    local command_id="$2"
    local max_wait=${3:-1800}  # Default 30 minutes
    
    local elapsed=0
    local interval=30
    
    print_info "⏳ Monitoring repository operations progress..."
    
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
                    print_progress "Repository operations still in progress... ($((elapsed / 60)) minutes elapsed)"
                fi
                ;;
            "Success")
                print_success "✅ Repository operations completed successfully!"
                
                # Get command output
                print_info "Repository Operations Summary:"
                aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" --query 'StandardOutputContent' --output text
                
                return 0
                ;;
            "Failed"|"Cancelled"|"TimedOut")
                print_error "Repository operations failed with status: $status"
                
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
    print_warning "Operations might still be running. Check manually."
    
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
    local operation="clone"
    
    # Initialize log file
    echo "Repository Deployment Log - $(date)" > "$LOG_FILE"
    
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
            --skip-repo-check)
                SKIP_REPO_CHECK=true
                shift
                ;;
            -d|--destroy)
                DESTROY=true
                shift
                ;;
            -l|--list-repos)
                list_repos
                exit 0
                ;;
            --add-repo)
                add_repo
                exit 0
                ;;
            --update-repos)
                operation="update"
                shift
                ;;
            --pull-repos)
                operation="pull"
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
    
    print_info "🚀 Starting staged repository $operation"
    print_info "Environment: $ENVIRONMENT"
    print_info "Instance ID: $instance_id"
    print_info "Operation: $operation"
    
    # Check prerequisites
    check_prerequisites
    
    # Validate instance
    validate_instance "$instance_id"
    
    # List configured repositories
    list_repos
    
    if [ ${#REPO_URLS[@]} -eq 0 ]; then
        print_warning "No repositories configured. Use --add-repo to add repositories."
        exit 0
    fi
    
    # Validate repository URLs (unless skipped)
    if [[ "$SKIP_REPO_CHECK" != true ]]; then
        validate_repo_urls
    fi
    
    # Deploy repositories
    print_info "📦 Stage 1: $operation repositories..."
    local command_id=$(deploy_repos "$instance_id" "$operation")
    
    # Monitor deployment
    print_info "📦 Stage 2: Monitoring $operation progress..."
    if monitor_repos "$instance_id" "$command_id"; then
        print_success "✅ Repository $operation completed successfully!"
    else
        print_warning "⚠️ Repository $operation may have issues. Check logs."
    fi
    
    # Display connection information
    get_connection_info "$instance_id"
    
    print_success "✅ Repository $operation process completed!"
    print_info "Check the log file for detailed information: $LOG_FILE"
}

# Execute main function
main "$@"
