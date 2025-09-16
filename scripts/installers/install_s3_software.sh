#!/bin/bash

# S3 Software Installation Controller Script
# This script orchestrates downloading and installing software from S3 using SSM documents
# It validates S3 objects, downloads installers, and executes installation via SSM

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
LOG_FILE="$SCRIPT_DIR/s3_software_install_$(date +%Y%m%d_%H%M%S).log"
STATE_FILE="$SCRIPT_DIR/installation_state.json"

# Default values
DRY_RUN=false
SKIP_VALIDATION=false
SKIP_DOWNLOAD=false
SKIP_INSTALL=false
AUTO_APPROVE=false
PARALLEL_DOWNLOADS=false
AWS_REGION="${AWS_REGION:-us-east-1}"

# S3 Access Point configuration
S3_ACCESS_POINT_ARN="${S3_ACCESS_POINT_ARN:-arn:aws:s3:us-east-1:326105557351:accesspoint/test-ap-2}"

# SSM Document names (these must be pre-registered in AWS SSM)
SSM_DOC_DOWNLOAD="DownloadS3Installers"
SSM_DOC_INSTALL_MSI="InstallMSISoftware"
SSM_DOC_INSTALL_EXE="InstallEXESoftware"

# Software configuration arrays
declare -a SOFTWARE_KEYS=(
    "CMake/Windows x86_64/Version 4.1.1/cmake-4.1.1-windows-x86_64.msi"
    "Git/Windows x86_64/Version 2.51.0/Git-2.51.0-64-bit.exe"
    "NASM/Windows x86_64/Version 2.16.03/nasm-2.16.03-installer-x64.exe"
    "Python Manager/Windows x86_64/Version 25.0b14/python-manager-25.0b14.msi"
    "Strawberry Perl/Windows x86_64/Version 5.40.2.1/strawberry-perl-5.40.2.1-64bit.msi"
)

declare -a SOFTWARE_NAMES=(
    "CMake"
    "Git for Windows"
    "NASM Assembler"
    "Python Manager"
    "Strawberry Perl"
)

declare -a SOFTWARE_TYPES=(
    "msi"
    "exe"
    "exe"
    "msi"
    "msi"
)

declare -a SOFTWARE_ARGS=(
    "/quiet /norestart"
    "/VERYSILENT /NORESTART"
    "/S"
    "/quiet /norestart"
    "/quiet /norestart"
)

declare -a SOFTWARE_DESTINATIONS=(
    "C:\\cmake"
    "C:\\Program Files\\Git"
    "C:\\Program Files\\NASM"
    "C:\\Python"
    "C:\\Strawberry"
)

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

S3 Software Installation Controller
Orchestrates downloading and installing software from S3 using SSM documents.

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Perform validation only, don't execute
    --skip-validation       Skip S3 object validation
    --skip-download         Skip download phase (assume already downloaded)
    --skip-install          Skip installation phase (download only)
    -a, --auto-approve      Auto-approve all operations
    -p, --parallel          Download files in parallel
    -r, --region            AWS region [default: us-east-1]
    -l, --list              List configured software
    -s, --status            Check installation status
    -c, --cleanup           Clean up temporary files and SSM documents
    --register-documents    Register SSM documents in AWS

REQUIRED:
    instance-id             EC2 instance ID to install software on

EXAMPLES:
    $0 i-0abc123def456789                     Full installation workflow
    $0 -d i-0abc123def456789                   Dry run (validation only)
    $0 --skip-validation i-0abc123def456789    Skip S3 validation
    $0 -l                                       List configured software
    $0 -s i-0abc123def456789                   Check installation status
    $0 --register-documents                    Register SSM documents

WORKFLOW:
    1. Validates S3 objects exist and are accessible
    2. Downloads all installers to the target instance
    3. Installs software based on type (.msi or .exe)
    4. Reports installation status

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - SSM Agent running on target instance
    - SSM documents registered (use --register-documents)
    - S3 access for the instance IAM role

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
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Please install: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
        print_error "AWS credentials not configured or expired"
        print_info "Please run: aws configure"
        exit 1
    fi
    
    # Get account info
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    local caller_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    
    print_success "Prerequisites check passed"
    print_info "AWS Account: $account_id"
    print_info "Caller: $caller_arn"
    print_info "Region: $AWS_REGION"
}

# Function to validate instance
validate_instance() {
    local instance_id="$1"
    
    print_info "Validating instance: $instance_id"
    
    # Check instance exists and is running
    local instance_info=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].{State:State.Name,Platform:Platform,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}' \
        --output json 2>/dev/null || echo "{}")
    
    if [[ "$instance_info" == "{}" ]]; then
        print_error "Instance $instance_id not found"
        return 1
    fi
    
    local state=$(echo "$instance_info" | jq -r '.State')
    local platform=$(echo "$instance_info" | jq -r '.Platform // "linux"')
    local private_ip=$(echo "$instance_info" | jq -r '.PrivateIp')
    local public_ip=$(echo "$instance_info" | jq -r '.PublicIp // "N/A"')
    
    if [[ "$state" != "running" ]]; then
        print_error "Instance is not running (state: $state)"
        return 1
    fi
    
    if [[ "$platform" != "windows" ]]; then
        print_error "Instance is not Windows (platform: $platform)"
        print_info "This script is designed for Windows instances only"
        return 1
    fi
    
    # Check SSM agent status
    local ssm_info=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$instance_id" \
        --region "$AWS_REGION" \
        --query 'InstanceInformationList[0].{PingStatus:PingStatus,Platform:PlatformType,Version:PlatformVersion}' \
        --output json 2>/dev/null || echo "{}")
    
    if [[ "$ssm_info" == "{}" ]] || [[ "$ssm_info" == "null" ]]; then
        print_error "SSM Agent not found or not running on instance"
        print_info "Please ensure SSM Agent is installed and running"
        return 1
    fi
    
    local ssm_status=$(echo "$ssm_info" | jq -r '.PingStatus // "Unknown"')
    
    if [[ "$ssm_status" != "Online" ]]; then
        print_error "SSM Agent is not online (status: $ssm_status)"
        return 1
    fi
    
    print_success "Instance validation passed"
    print_info "Instance ID: $instance_id"
    print_info "State: $state"
    print_info "Platform: $platform"
    print_info "Private IP: $private_ip"
    print_info "Public IP: $public_ip"
    print_info "SSM Status: $ssm_status"
    
    return 0
}

# Function to validate S3 objects
validate_s3_objects() {
    print_info "Validating S3 objects..."
    
    local validation_failed=false
    local validated_count=0
    local failed_count=0
    
    for i in "${!SOFTWARE_KEYS[@]}"; do
        local key="${SOFTWARE_KEYS[$i]}"
        local name="${SOFTWARE_NAMES[$i]}"
        
        print_progress "Checking: $name"
        
        # Check if object exists using head-object
        if aws s3api head-object \
            --bucket "$S3_ACCESS_POINT_ARN" \
            --key "$key" \
            --region "$AWS_REGION" &>/dev/null; then
            
            # Get object metadata
            local object_info=$(aws s3api head-object \
                --bucket "$S3_ACCESS_POINT_ARN" \
                --key "$key" \
                --region "$AWS_REGION" \
                --output json)
            
            local size=$(echo "$object_info" | jq -r '.ContentLength // 0')
            local size_mb=$((size / 1024 / 1024))
            local last_modified=$(echo "$object_info" | jq -r '.LastModified // "Unknown"')
            
            print_success "  ✅ $name - Valid (${size_mb}MB, Modified: $last_modified)"
            ((validated_count++))
        else
            print_error "  ❌ $name - Not found or not accessible"
            ((failed_count++))
            validation_failed=true
        fi
    done
    
    print_info "Validation Summary: $validated_count valid, $failed_count failed"
    
    if [[ "$validation_failed" == true ]] && [[ "$SKIP_VALIDATION" != true ]]; then
        print_error "S3 validation failed. Use --skip-validation to bypass."
        return 1
    fi
    
    return 0
}

# Function to register SSM documents
register_ssm_documents() {
    print_info "Registering SSM documents..."
    
    local docs_to_register=(
        "$SSM_DOC_DOWNLOAD:$SCRIPT_DIR/ssm_doc_download_s3_installers.json"
        "$SSM_DOC_INSTALL_MSI:$SCRIPT_DIR/ssm_doc_install_msi.json"
        "$SSM_DOC_INSTALL_EXE:$SCRIPT_DIR/ssm_doc_install_exe.json"
    )
    
    for doc_spec in "${docs_to_register[@]}"; do
        local doc_name="${doc_spec%%:*}"
        local doc_file="${doc_spec##*:}"
        
        if [[ ! -f "$doc_file" ]]; then
            print_error "SSM document file not found: $doc_file"
            continue
        fi
        
        print_progress "Registering: $doc_name"
        
        # Check if document already exists
        if aws ssm describe-document \
            --name "$doc_name" \
            --region "$AWS_REGION" &>/dev/null; then
            print_warning "  Document already exists, updating..."
            
            # Update existing document
            if aws ssm update-document \
                --name "$doc_name" \
                --content "file://$doc_file" \
                --document-version "\$LATEST" \
                --region "$AWS_REGION" &>/dev/null; then
                print_success "  ✅ Updated: $doc_name"
            else
                print_error "  ❌ Failed to update: $doc_name"
            fi
        else
            # Create new document
            if aws ssm create-document \
                --name "$doc_name" \
                --document-type "Command" \
                --content "file://$doc_file" \
                --document-format "JSON" \
                --region "$AWS_REGION" &>/dev/null; then
                print_success "  ✅ Created: $doc_name"
            else
                print_error "  ❌ Failed to create: $doc_name"
            fi
        fi
    done
    
    print_success "SSM document registration complete"
}

# Function to download installers
download_installers() {
    local instance_id="$1"
    
    print_info "📦 Phase 1: Downloading installers from S3..."
    
    # Prepare parameters for SSM document
    local keys_json=$(printf '%s\n' "${SOFTWARE_KEYS[@]}" | jq -R . | jq -s -c .)
    local names_json=$(printf '%s\n' "${SOFTWARE_NAMES[@]}" | jq -R . | jq -s -c .)
    local destinations_json=$(printf '%s\n' "${SOFTWARE_DESTINATIONS[@]}" | jq -R . | jq -s -c .)
    
    # Execute download SSM document
    print_progress "Executing download command..."
    
    local command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "$SSM_DOC_DOWNLOAD" \
        --parameters "{
            \"s3BucketArn\": [\"$S3_ACCESS_POINT_ARN\"],
            \"softwareKeys\": $keys_json,
            \"softwareNames\": $names_json,
            \"downloadPaths\": $destinations_json,
            \"region\": [\"$AWS_REGION\"]
        }" \
        --timeout-seconds 1800 \
        --region "$AWS_REGION" \
        --output text \
        --query 'Command.CommandId')
    
    if [[ -z "$command_id" ]]; then
        print_error "Failed to send download command"
        return 1
    fi
    
    print_info "Download command ID: $command_id"
    
    # Monitor download progress
    if monitor_command "$instance_id" "$command_id" "download"; then
        print_success "✅ Downloads completed successfully"
        return 0
    else
        print_error "❌ Downloads failed"
        return 1
    fi
}

# Function to install software
install_software() {
    local instance_id="$1"
    
    print_info "📦 Phase 2: Installing software..."
    
    local install_success=true
    
    for i in "${!SOFTWARE_KEYS[@]}"; do
        local key="${SOFTWARE_KEYS[$i]}"
        local name="${SOFTWARE_NAMES[$i]}"
        local type="${SOFTWARE_TYPES[$i]}"
        local args="${SOFTWARE_ARGS[$i]}"
        local destination="${SOFTWARE_DESTINATIONS[$i]}"
        
        # Extract filename from key
        local filename=$(basename "$key")
        local installer_path="$destination\\$filename"
        
        print_progress "Installing $name ($type)..."
        
        # Select appropriate SSM document based on type
        local doc_name=""
        case "$type" in
            msi)
                doc_name="$SSM_DOC_INSTALL_MSI"
                ;;
            exe)
                doc_name="$SSM_DOC_INSTALL_EXE"
                ;;
            *)
                print_warning "Unknown installer type: $type for $name"
                continue
                ;;
        esac
        
        # Execute installation
        local command_id=$(aws ssm send-command \
            --instance-ids "$instance_id" \
            --document-name "$doc_name" \
            --parameters "{
                \"installerPath\": [\"$installer_path\"],
                \"softwareName\": [\"$name\"],
                \"installArgs\": [\"$args\"],
                \"destinationPath\": [\"$destination\"]
            }" \
            --timeout-seconds 900 \
            --region "$AWS_REGION" \
            --output text \
            --query 'Command.CommandId')
        
        if [[ -z "$command_id" ]]; then
            print_error "Failed to send install command for $name"
            install_success=false
            continue
        fi
        
        # Monitor installation
        if monitor_command "$instance_id" "$command_id" "install-$name"; then
            print_success "  ✅ $name installed successfully"
        else
            print_error "  ❌ $name installation failed"
            install_success=false
        fi
    done
    
    if [[ "$install_success" == true ]]; then
        print_success "✅ All software installed successfully"
        return 0
    else
        print_warning "⚠️ Some installations failed"
        return 1
    fi
}

# Function to monitor SSM command execution
monitor_command() {
    local instance_id="$1"
    local command_id="$2"
    local operation="$3"
    local max_wait=${4:-1800}  # Default 30 minutes
    
    local elapsed=0
    local interval=10
    local last_status=""
    
    print_progress "⏳ Monitoring $operation..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        # Get command status
        local command_info=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --region "$AWS_REGION" \
            --output json 2>/dev/null || echo "{}")
        
        if [[ "$command_info" == "{}" ]]; then
            print_warning "Command not found yet, waiting..."
            sleep $interval
            elapsed=$((elapsed + interval))
            continue
        fi
        
        local status=$(echo "$command_info" | jq -r '.Status // "Unknown"')
        
        # Print status update only if changed
        if [[ "$status" != "$last_status" ]]; then
            print_progress "Status: $status"
            last_status="$status"
        fi
        
        case "$status" in
            Success)
                # Get output
                local output=$(echo "$command_info" | jq -r '.StandardOutputContent // ""' | tail -20)
                if [[ -n "$output" ]]; then
                    echo "Output (last 20 lines):"
                    echo "$output"
                fi
                return 0
                ;;
            Failed|TimedOut|Cancelled|AccessDenied|DeliveryTimedOut)
                # Get error details
                local error_output=$(echo "$command_info" | jq -r '.StandardErrorContent // ""')
                if [[ -n "$error_output" ]]; then
                    print_error "Error details:"
                    echo "$error_output"
                fi
                return 1
                ;;
            InProgress|Pending|Delayed)
                if [[ $((elapsed % 60)) -eq 0 ]] && [[ $elapsed -gt 0 ]]; then
                    print_info "Still $status... ($((elapsed/60)) minutes elapsed)"
                fi
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_warning "Operation timed out after $((max_wait/60)) minutes"
    return 1
}

# Function to check installation status
check_installation_status() {
    local instance_id="$1"
    
    print_info "Checking installation status..."
    
    # Check for installed software
    local check_command=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=[
            "$software = @()",
            "if (Test-Path \"C:\\cmake\\cmake.exe\") { $software += \"CMake\" }",
            "if (Test-Path \"C:\\Program Files\\Git\\bin\\git.exe\") { $software += \"Git\" }",
            "if (Test-Path \"C:\\Program Files\\NASM\\nasm.exe\") { $software += \"NASM\" }",
            "if (Test-Path \"C:\\Python\\python.exe\") { $software += \"Python\" }",
            "if (Test-Path \"C:\\Strawberry\\perl\\bin\\perl.exe\") { $software += \"Perl\" }",
            "if ($software.Count -eq 0) { \"No software installed\" } else { \"Installed: \" + ($software -join \", \") }"
        ]' \
        --region "$AWS_REGION" \
        --output text \
        --query 'Command.CommandId')
    
    if [[ -n "$check_command" ]]; then
        sleep 5
        
        local result=$(aws ssm get-command-invocation \
            --command-id "$check_command" \
            --instance-id "$instance_id" \
            --region "$AWS_REGION" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "Check failed")
        
        print_info "Installation Status:"
        echo "$result"
    fi
}

# Function to list configured software
list_configured_software() {
    print_info "Configured Software:"
    print_info "==================="
    
    for i in "${!SOFTWARE_KEYS[@]}"; do
        local key="${SOFTWARE_KEYS[$i]}"
        local name="${SOFTWARE_NAMES[$i]}"
        local type="${SOFTWARE_TYPES[$i]}"
        local args="${SOFTWARE_ARGS[$i]}"
        local destination="${SOFTWARE_DESTINATIONS[$i]}"
        
        echo ""
        echo "[$((i+1))] $name"
        echo "    Type: $type"
        echo "    S3 Key: $key"
        echo "    Install Args: $args"
        echo "    Destination: $destination"
    done
    echo ""
}

# Function to clean up resources
cleanup_resources() {
    print_info "Cleaning up resources..."
    
    # Remove state file
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        print_info "Removed state file"
    fi
    
    # Clean up old log files (keep last 10)
    local log_count=$(ls -1 "$SCRIPT_DIR"/s3_software_install_*.log 2>/dev/null | wc -l)
    if [[ $log_count -gt 10 ]]; then
        ls -1t "$SCRIPT_DIR"/s3_software_install_*.log | tail -n +11 | xargs rm -f
        print_info "Cleaned up old log files"
    fi
    
    print_success "Cleanup complete"
}

# Function to save state
save_state() {
    local instance_id="$1"
    local phase="$2"
    local status="$3"
    
    cat > "$STATE_FILE" <<EOF
{
    "instance_id": "$instance_id",
    "phase": "$phase",
    "status": "$status",
    "timestamp": "$(date -Iseconds)",
    "software_count": ${#SOFTWARE_KEYS[@]}
}
EOF
}

# Function to load state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo "{}"
    fi
}

# Main execution function
main() {
    local instance_id=""
    local action="install"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --skip-download)
                SKIP_DOWNLOAD=true
                shift
                ;;
            --skip-install)
                SKIP_INSTALL=true
                shift
                ;;
            -a|--auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            -p|--parallel)
                PARALLEL_DOWNLOADS=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -l|--list)
                list_configured_software
                exit 0
                ;;
            -s|--status)
                action="status"
                shift
                ;;
            -c|--cleanup)
                cleanup_resources
                exit 0
                ;;
            --register-documents)
                check_prerequisites
                register_ssm_documents
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$instance_id" ]]; then
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
    
    # Validate instance ID
    if [[ -z "$instance_id" ]]; then
        print_error "Instance ID is required"
        show_usage
        exit 1
    fi
    
    print_info "🚀 S3 Software Installation Controller"
    print_info "Instance: $instance_id"
    print_info "Region: $AWS_REGION"
    print_info "Software packages: ${#SOFTWARE_KEYS[@]}"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Validate instance
    if ! validate_instance "$instance_id"; then
        print_error "Instance validation failed"
        exit 1
    fi
    
    # Handle different actions
    if [[ "$action" == "status" ]]; then
        check_installation_status "$instance_id"
        exit 0
    fi
    
    # Dry run mode
    if [[ "$DRY_RUN" == true ]]; then
        print_info "DRY RUN MODE - No changes will be made"
        
        # List software
        list_configured_software
        
        # Validate S3 objects
        if [[ "$SKIP_VALIDATION" != true ]]; then
            validate_s3_objects
        fi
        
        print_success "Dry run complete"
        exit 0
    fi
    
    # Confirm installation
    if [[ "$AUTO_APPROVE" != true ]]; then
        echo ""
        print_warning "This will download and install ${#SOFTWARE_KEYS[@]} software packages"
        echo -n "Do you want to continue? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Phase 1: Validate S3 objects
    if [[ "$SKIP_VALIDATION" != true ]]; then
        print_info "📋 Phase 1: Validating S3 objects..."
        save_state "$instance_id" "validation" "in_progress"
        
        if validate_s3_objects; then
            save_state "$instance_id" "validation" "completed"
            print_success "✅ Validation completed"
        else
            save_state "$instance_id" "validation" "failed"
            print_error "❌ Validation failed"
            exit 1
        fi
    else
        print_info "Skipping S3 validation"
    fi
    
    # Phase 2: Download installers
    if [[ "$SKIP_DOWNLOAD" != true ]]; then
        print_info "📥 Phase 2: Downloading installers..."
        save_state "$instance_id" "download" "in_progress"
        
        if download_installers "$instance_id"; then
            save_state "$instance_id" "download" "completed"
            print_success "✅ Downloads completed"
        else
            save_state "$instance_id" "download" "failed"
            print_error "❌ Downloads failed"
            exit 1
        fi
    else
        print_info "Skipping download phase"
    fi
    
    # Phase 3: Install software
    if [[ "$SKIP_INSTALL" != true ]]; then
        print_info "🔧 Phase 3: Installing software..."
        save_state "$instance_id" "install" "in_progress"
        
        if install_software "$instance_id"; then
            save_state "$instance_id" "install" "completed"
            print_success "✅ Installation completed"
        else
            save_state "$instance_id" "install" "failed"
            print_warning "⚠️ Some installations failed"
        fi
    else
        print_info "Skipping installation phase"
    fi
    
    # Final status check
    print_info "📊 Final Status Check..."
    check_installation_status "$instance_id"
    
    print_success "✅ S3 Software Installation workflow complete!"
    print_info "Log file: $LOG_FILE"
    print_info "State file: $STATE_FILE"
}

# Execute main function
main "$@"