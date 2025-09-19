#!/bin/bash

# Debug CMake Download Script
# Simplified script to debug CMake download from S3 access point
#
# REQUIREMENTS:
#   - AWS CLI installed and configured
#   - jq installed for JSON processing  
#   - ssm_doc_download_cmake_debug.json file in the same directory as this script

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
LOG_FILE="$SCRIPT_DIR/cmake_debug_$(date +%Y%m%d_%H%M%S).log"

# Default values
AWS_REGION="${AWS_REGION:-us-east-1}"

# S3 Access Point configuration
S3_ACCESS_POINT_ARN="${S3_ACCESS_POINT_ARN:-arn:aws:s3:us-east-1:326105557351:accesspoint/test-ap-2}"

# Execution mode configuration
SEQUENTIAL_EXECUTION=true
CONTINUE_ON_ERROR=false
EXECUTION_MODE="debug"  # "debug" for single document, "individual" for separate documents

# SSM Document name for debugging (single document approach)
SSM_DOC_DEBUG="DebugCMakeDownload"

# SSM Documents directory for individual documents
SSM_DOCS_DIR="$SCRIPT_DIR/ssm"

# Software configuration arrays
declare -a SOFTWARE_KEYS=(
    "CMake/Windows x86_64/Version 4.1.1/cmake-4.1.1-windows-x86_64.msi"
    "Git/Windows x86_64/Version 2.51.0/Git-2.51.0-64-bit.exe"
)

declare -a SOFTWARE_NAMES=(
    "CMake"
    "Git for Windows"
)

declare -a SOFTWARE_DESTINATIONS=(
    "C:/downloads/cmake"
    "C:/downloads/git"
)

# Individual installer configuration (for separate SSM documents approach)
# Define installers in order of installation
declare -a INSTALLER_ORDER=(
    "cmake"
    "git"
    "nasm"
    "python_manager"
    "strawberry_perl"
)

# Installer configurations using associative arrays
declare -A INSTALLER_CONFIGS=(
    ["cmake_name"]="CMake"
    ["cmake_key"]="CMake/Windows x86_64/Version 4.1.1/cmake-4.1.1-windows-x86_64.msi"
    ["cmake_destination"]="C:/downloads/cmake"
    ["cmake_doc_name"]="InstallCMake"
    ["cmake_doc_file"]="ssm_doc_download_cmake.json"
    
    ["git_name"]="Git for Windows"
    ["git_key"]="Git/Windows x86_64/Version 2.51.0/Git-2.51.0-64-bit.exe"
    ["git_destination"]="C:/downloads/git"
    ["git_doc_name"]="InstallGit"
    ["git_doc_file"]="ssm_doc_download_git.json"
    
    ["nasm_name"]="NASM"
    ["nasm_key"]="NASM/Windows x86_64/Version 2.16.03/nasm-2.16.03-installer-x64.exe"
    ["nasm_destination"]="C:/downloads/nasm"
    ["nasm_doc_name"]="InstallNASM"
    ["nasm_doc_file"]="ssm_doc_download_nasm.json"
    
    ["python_manager_name"]="Python Manager"
    ["python_manager_key"]="Python Manager/Windows x86_64/Version 25.0b14/python-manager-25.0b14.msi"
    ["python_manager_destination"]="C:/downloads/python"
    ["python_manager_doc_name"]="InstallPythonManager"
    ["python_manager_doc_file"]="ssm_doc_download_python_manager.json"
    
    ["strawberry_perl_name"]="Strawberry Perl"
    ["strawberry_perl_key"]="Strawberry Perl/Windows x86_64/Version 5.40.2.1/strawberry-perl-5.40.2.1-64bit.msi"
    ["strawberry_perl_destination"]="C:/downloads/perl"
    ["strawberry_perl_doc_name"]="InstallStrawberryPerl"
    ["strawberry_perl_doc_file"]="ssm_doc_download_strawberry_perl.json"
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

# Function to list SSM documents
list_ssm_documents() {
    print_info "Listing SSM documents matching: $SSM_DOC_DEBUG"
    
    # List all Command documents if specific one not found
    local docs
    docs=$(aws ssm list-documents \
        --document-filter-list "key=DocumentType,value=Command" \
        --region "$AWS_REGION" \
        --output json 2>/tmp/ssm_list_error.txt)
    
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        local error_output=$(cat /tmp/ssm_list_error.txt 2>/dev/null || echo "Unknown error")
        print_error "Failed to list documents: $error_output"
        rm -f /tmp/ssm_list_error.txt
        return 1
    fi
    
    rm -f /tmp/ssm_list_error.txt
    
    # Validate JSON before parsing
    if ! echo "$docs" | jq empty 2>/dev/null; then
        print_error "Invalid JSON response from AWS CLI"
        return 1
    fi
    
    # Check for our specific document
    local our_doc=$(echo "$docs" | jq --arg name "$SSM_DOC_DEBUG" '.DocumentIdentifiers[] | select(.Name == $name)' 2>/dev/null)
    
    if [[ -n "$our_doc" ]]; then
        print_success "Found document: $SSM_DOC_DEBUG"
        echo "$our_doc" | jq -r '"  - Name: \(.Name)\n  - Version: \(.DocumentVersion)\n  - Owner: \(.Owner)\n  - Platform: \(.PlatformTypes // ["N/A"] | join(", "))"'
    else
        print_warning "Document not found: $SSM_DOC_DEBUG"
        
        # Show recent Command documents for reference
        print_info "Recent Command documents in account:"
        echo "$docs" | jq -r '.DocumentIdentifiers[:5][] | "  - \(.Name) (Owner: \(.Owner))"' 2>/dev/null || echo "  No documents found"
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] <instance-id>

S3 Installers Download Script
Supports both debug mode (single document) and individual installer mode.

OPTIONS:
    -h, --help              Show this help message
    -r, --region            AWS region [default: us-east-1]
    --s3-arn                S3 Access Point ARN
    --mode                  Execution mode: "debug" (single doc) or "individual" (separate docs) [default: debug]
    --parallel              Run installations in parallel (individual mode only)
    --continue-on-error     Continue with next installer if one fails
    --register-document     Register SSM document(s) (always creates new version)
    --register-only         Only register SSM documents, don't execute
    --list-documents        List existing SSM documents
    --list-installers       List configured installers (individual mode)
    --verify-document       Verify SSM document is ready
    --status                Check download/installation status
    --cleanup               Delete all registered SSM documents

REQUIRED:
    instance-id             EC2 instance ID to download/install software on

EXAMPLES:
    # Debug mode (single document approach)
    $0 i-0abc123def456789                     Download CMake and Git using single document
    $0 --register-document                    Register debug SSM document
    $0 --list-documents                       List SSM documents
    
    # Individual mode (separate documents approach)
    $0 --mode individual i-0abc123def456789   Install all software using separate documents
    $0 --mode individual --parallel i-0abc123def456789  Install in parallel
    $0 --mode individual --register-only      Only register individual SSM documents
    $0 --mode individual --list-installers    List all configured installers
    
    # Common operations
    $0 --verify-document                      Verify document is ready
    $0 --status i-0abc123def456789            Check installation status
    $0 --cleanup                              Delete all SSM documents

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
    
    if [[ "$validation_failed" == true ]]; then
        print_error "S3 validation failed"
        return 1
    fi
    
    return 0
}

# Function to create SSM document JSON
create_ssm_document_json() {
    cat <<'SSMDOC'
{
    "schemaVersion": "2.2",
    "description": "Debug: Download multiple installers from S3 access point",
    "parameters": {
        "s3BucketArn": {
            "type": "String",
            "description": "S3 access point ARN",
            "allowedPattern": "^arn:aws:s3:[a-z0-9-]+:[0-9]+:accesspoint/[a-zA-Z0-9-]+$"
        },
        "softwareKeys": {
            "type": "StringList",
            "description": "List of S3 object keys for software installers"
        },
        "softwareNames": {
            "type": "StringList",
            "description": "List of software names (corresponding to keys)"
        },
        "downloadPaths": {
            "type": "StringList",
            "description": "List of destination paths for downloads"
        },
        "region": {
            "type": "String",
            "description": "AWS region",
            "default": "us-east-1"
        }
    },
    "mainSteps": [
        {
            "action": "aws:runPowerShellScript",
            "name": "downloadInstallers",
            "inputs": {
                "timeoutSeconds": "1800",
                "runCommand": [
                    "# Debug: Multi-Installer Download Script",
                    "",
                    "# Get parameters from SSM",
                    "$S3BucketArn = '{{ s3BucketArn }}'",
                    "$SoftwareKeys = {{ softwareKeys }}",
                    "$SoftwareNames = {{ softwareNames }}",
                    "$DownloadPaths = {{ downloadPaths }}",
                    "$Region = '{{ region }}'",
                    "",
                    "# Set up logging",
                    "$LogDir = \"C:\\logs\"",
                    "if (!(Test-Path $LogDir)) {",
                    "    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null",
                    "}",
                    "",
                    "$LogFile = \"$LogDir\\multi-download-debug-$(Get-Date -Format 'yyyyMMdd-HHmmss').log\"",
                    "",
                    "function Write-Log {",
                    "    param([string]$Message, [string]$Level = \"INFO\")",
                    "    $Timestamp = Get-Date -Format \"yyyy-MM-dd HH:mm:ss\"",
                    "    $LogEntry = \"[$Timestamp] [$Level] $Message\"",
                    "    Write-Host $LogEntry",
                    "    Add-Content -Path $LogFile -Value $LogEntry",
                    "}",
                    "",
                    "# Debug: Print all parameter values",
                    "Write-Log \"========================================\" \"INFO\"",
                    "Write-Log \"Multi-Installer Download Debug Session\" \"INFO\"",
                    "Write-Log \"========================================\" \"INFO\"",
                    "Write-Log \"S3BucketArn: $S3BucketArn\" \"INFO\"",
                    "Write-Log \"SoftwareKeys count: $($SoftwareKeys.Count)\" \"INFO\"",
                    "Write-Log \"SoftwareNames count: $($SoftwareNames.Count)\" \"INFO\"",
                    "Write-Log \"DownloadPaths count: $($DownloadPaths.Count)\" \"INFO\"",
                    "Write-Log \"Region: $Region\" \"INFO\"",
                    "",
                    "# Test AWS CLI availability",
                    "Write-Log \"Testing AWS CLI...\" \"INFO\"",
                    "try {",
                    "    $awsVersion = & \"C:\\Program Files\\Amazon\\AWSCLIV2\\aws.exe\" --version 2>&1",
                    "    Write-Log \"AWS CLI available: $awsVersion\" \"SUCCESS\"",
                    "} catch {",
                    "    Write-Log \"AWS CLI not available: $_\" \"ERROR\"",
                    "    exit 1",
                    "}",
                    "",
                    "# Test AWS credentials",
                    "Write-Log \"Testing AWS credentials...\" \"INFO\"",
                    "try {",
                    "    $callerIdentity = & \"C:\\Program Files\\Amazon\\AWSCLIV2\\aws.exe\" sts get-caller-identity --region $Region 2>&1",
                    "    if ($LASTEXITCODE -eq 0) {",
                    "        Write-Log \"AWS credentials valid: $callerIdentity\" \"SUCCESS\"",
                    "    } else {",
                    "        Write-Log \"AWS credentials invalid: $callerIdentity\" \"ERROR\"",
                    "        exit 1",
                    "    }",
                    "} catch {",
                    "    Write-Log \"Failed to verify AWS credentials: $_\" \"ERROR\"",
                    "    exit 1",
                    "}",
                    "",
                    "# Initialize counters",
                    "$SuccessCount = 0",
                    "$FailureCount = 0",
                    "",
                    "# Download each file",
                    "for ($i = 0; $i -lt $SoftwareKeys.Count; $i++) {",
                    "    $Key = $SoftwareKeys[$i]",
                    "    $Name = if ($i -lt $SoftwareNames.Count) { $SoftwareNames[$i] } else { \"Software $($i+1)\" }",
                    "    $DestPath = if ($i -lt $DownloadPaths.Count) { $DownloadPaths[$i] } else { \"C:\\downloads\" }",
                    "    ",
                    "    Write-Log \"\" \"INFO\"",
                    "    Write-Log \"Processing file $($i+1)/$($SoftwareKeys.Count): $Name\" \"INFO\"",
                    "    Write-Log \"----------------------------------------\" \"INFO\"",
                    "    ",
                    "    # Create destination directory",
                    "    Write-Log \"Creating destination directory: $DestPath\" \"INFO\"",
                    "    if (!(Test-Path $DestPath)) {",
                    "        New-Item -ItemType Directory -Path $DestPath -Force | Out-Null",
                    "        Write-Log \"Directory created successfully\" \"SUCCESS\"",
                    "    } else {",
                    "        Write-Log \"Directory already exists\" \"INFO\"",
                    "    }",
                    "    ",
                    "    # Extract filename from S3 key",
                    "    $FileName = Split-Path $Key -Leaf",
                    "    $FilePath = Join-Path $DestPath $FileName",
                    "    ",
                    "    Write-Log \"Downloading: $Name\" \"INFO\"",
                    "    Write-Log \"  S3 Key: $Key\" \"INFO\"",
                    "    Write-Log \"  Local Path: $FilePath\" \"INFO\"",
                    "    ",
                    "    # Download using AWS CLI",
                    "    $awsExe = \"C:\\Program Files\\Amazon\\AWSCLIV2\\aws.exe\"",
                    "    $awsArgs = @(\"s3api\", \"get-object\", \"--bucket\", $S3BucketArn, \"--key\", $Key, $FilePath, \"--region\", $Region)",
                    "    $awsCommand = \"$awsExe s3api get-object --bucket $S3BucketArn --key $Key $FilePath --region $Region\"",
                    "    Write-Log \"Executing: $awsCommand\" \"INFO\"",
                    "    ",
                    "    try {",
                    "        $result = & $awsExe $awsArgs 2>&1",
                    "        $exitCode = $LASTEXITCODE",
                    "        ",
                    "        Write-Log \"AWS CLI exit code: $exitCode\" \"INFO\"",
                    "        Write-Log \"AWS CLI output: $result\" \"INFO\"",
                    "        ",
                    "        if ($exitCode -eq 0 -and (Test-Path $FilePath)) {",
                    "            $FileInfo = Get-Item $FilePath",
                    "            $FileSizeMB = [math]::Round($FileInfo.Length / 1MB, 2)",
                    "            ",
                    "            Write-Log \"✅ Download completed successfully!\" \"SUCCESS\"",
                    "            Write-Log \"  File: $FilePath\" \"SUCCESS\"",
                    "            Write-Log \"  Size: $FileSizeMB MB\" \"SUCCESS\"",
                    "            Write-Log \"  Created: $($FileInfo.CreationTime)\" \"SUCCESS\"",
                    "            ",
                    "            $SuccessCount++",
                    "        } else {",
                    "            Write-Log \"❌ Download failed\" \"ERROR\"",
                    "            Write-Log \"  Exit code: $exitCode\" \"ERROR\"",
                    "            Write-Log \"  Output: $result\" \"ERROR\"",
                    "            ",
                    "            $FailureCount++",
                    "        }",
                    "    } catch {",
                    "        Write-Log \"❌ Download error: $_\" \"ERROR\"",
                    "        $FailureCount++",
                    "    }",
                    "}",
                    "",
                    "# Generate summary",
                    "Write-Log \"\" \"INFO\"",
                    "Write-Log \"========================================\" \"INFO\"",
                    "Write-Log \"Download Summary\" \"INFO\"",
                    "Write-Log \"========================================\" \"INFO\"",
                    "Write-Log \"Total files: $($SoftwareKeys.Count)\" \"INFO\"",
                    "Write-Log \"Successful downloads: $SuccessCount\" \"SUCCESS\"",
                    "Write-Log \"Failed downloads: $FailureCount\" $(if ($FailureCount -gt 0) { \"ERROR\" } else { \"INFO\" })",
                    "",
                    "if ($FailureCount -eq 0) {",
                    "    Write-Log \"All downloads completed successfully!\" \"SUCCESS\"",
                    "    exit 0",
                    "} else {",
                    "    Write-Log \"Some downloads failed\" \"ERROR\"",
                    "    exit 1",
                    "}"
                ]
            }
        }
    ]
}
SSMDOC
}

# Function to verify SSM document
verify_ssm_document() {
    local doc_name="$1"
    
    print_info "Verifying SSM document: $doc_name"
    
    # Check if document exists - capture both stdout and stderr separately
    local doc_info
    local error_output
    
    doc_info=$(aws ssm describe-document \
        --name "$doc_name" \
        --region "$AWS_REGION" \
        --output json 2>/tmp/ssm_verify_error.txt)
    
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        error_output=$(cat /tmp/ssm_verify_error.txt 2>/dev/null || echo "Unknown error")
        print_error "Document does not exist or is not accessible"
        print_error "Error: $error_output"
        rm -f /tmp/ssm_verify_error.txt
        return 1
    fi
    
    rm -f /tmp/ssm_verify_error.txt
    
    # Validate JSON before parsing
    if ! echo "$doc_info" | jq empty 2>/dev/null; then
        print_error "Invalid JSON response from AWS CLI"
        print_error "Response: $doc_info"
        return 1
    fi
    
    # Parse document info
    local doc_status=$(echo "$doc_info" | jq -r '.Document.Status // "Unknown"' 2>/dev/null || echo "Unknown")
    local doc_type=$(echo "$doc_info" | jq -r '.Document.DocumentType // "Unknown"' 2>/dev/null || echo "Unknown")
    local doc_version=$(echo "$doc_info" | jq -r '.Document.DocumentVersion // "Unknown"' 2>/dev/null || echo "Unknown")
    
    print_info "Document Status: $doc_status"
    print_info "Document Type: $doc_type"
    print_info "Document Version: $doc_version"
    
    if [[ "$doc_status" != "Active" ]]; then
        print_error "Document is not active (status: $doc_status)"
        return 1
    fi
    
    print_success "Document verified successfully"
    return 0
}

# Function to cleanup all SSM documents
cleanup_ssm_documents() {
    print_info "🧹 Cleaning up all registered SSM documents..."
    
    # Get all Command documents owned by this account
    local docs
    docs=$(aws ssm list-documents \
        --document-filter-list "key=DocumentType,value=Command" \
        --region "$AWS_REGION" \
        --output json 2>/tmp/ssm_cleanup_error.txt)
    
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        local error_output=$(cat /tmp/ssm_cleanup_error.txt 2>/dev/null || echo "Unknown error")
        print_error "Failed to list documents for cleanup: $error_output"
        rm -f /tmp/ssm_cleanup_error.txt
        return 1
    fi
    
    rm -f /tmp/ssm_cleanup_error.txt
    
    # Validate JSON before parsing
    if ! echo "$docs" | jq empty 2>/dev/null; then
        print_error "Invalid JSON response from AWS CLI during cleanup"
        return 1
    fi
    
    # Get document names owned by this account
    local doc_names
    doc_names=$(echo "$docs" | jq -r '.DocumentIdentifiers[] | select(.Owner == "Self") | .Name' 2>/dev/null)
    
    if [[ -z "$doc_names" ]]; then
        print_info "No documents found to cleanup"
        return 0
    fi
    
    local deleted_count=0
    local failed_count=0
    
    # Delete each document
    while IFS= read -r doc_name; do
        if [[ -n "$doc_name" ]]; then
            print_progress "Deleting document: $doc_name"
            
            if aws ssm delete-document \
                --name "$doc_name" \
                --region "$AWS_REGION" 2>/tmp/ssm_delete_error.txt; then
                print_success "  ✅ Deleted: $doc_name"
                ((deleted_count++))
            else
                local delete_error=$(cat /tmp/ssm_delete_error.txt 2>/dev/null || echo "Unknown error")
                print_warning "  ⚠️  Failed to delete $doc_name: $delete_error"
                ((failed_count++))
            fi
            rm -f /tmp/ssm_delete_error.txt
        fi
    done <<< "$doc_names"
    
    print_info "Cleanup Summary: $deleted_count deleted, $failed_count failed"
    
    if [[ $failed_count -eq 0 ]]; then
        print_success "✅ All documents cleaned up successfully"
        return 0
    else
        print_warning "⚠️  Some documents could not be deleted"
        return 1
    fi
}

# Function to register SSM document (always creates new version)
register_ssm_document() {
    print_info "Registering debug SSM document: $SSM_DOC_DEBUG (always creates new version)"
    
    # Define path to SSM document JSON file
    local doc_file="$SCRIPT_DIR/ssm_doc_download_cmake_debug.json"
    
    # Check if document file exists
    if [[ ! -f "$doc_file" ]]; then
        print_error "SSM document file not found: $doc_file"
        print_info "Please ensure ssm_doc_download_cmake_debug.json exists in: $SCRIPT_DIR"
        return 1
    fi
    
    print_success "Found SSM document file: $doc_file"
    
    # Validate JSON structure
    if ! jq empty "$doc_file" 2>/dev/null; then
        print_error "SSM document file has invalid JSON"
        print_info "You can validate it with: jq . $doc_file"
        return 1
    fi
    
    print_success "JSON validation passed"
    
    # Always delete existing document to ensure new version
    print_progress "Checking for existing document..."
    local existing_doc
    existing_doc=$(aws ssm describe-document \
        --name "$SSM_DOC_DEBUG" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        print_info "Document already exists, deleting to create new version..."
        
        # Delete existing document
        if aws ssm delete-document \
            --name "$SSM_DOC_DEBUG" \
            --region "$AWS_REGION" 2>/tmp/ssm_delete_error.txt; then
            print_success "Old document deleted"
            sleep 3  # Wait for deletion to propagate
        else
            local delete_error=$(cat /tmp/ssm_delete_error.txt 2>/dev/null)
            print_warning "Could not delete old document: $delete_error"
            rm -f /tmp/ssm_delete_error.txt
        fi
    else
        print_info "No existing document found"
    fi
    
    # Create new document
    print_progress "Creating new SSM document..."
    local create_output
    create_output=$(aws ssm create-document \
        --name "$SSM_DOC_DEBUG" \
        --document-type "Command" \
        --content "file://$doc_file" \
        --document-format "JSON" \
        --region "$AWS_REGION" \
        --output json 2>/tmp/ssm_create_error.txt)
    
    local create_exit_code=$?
    
    if [[ $create_exit_code -eq 0 ]]; then
        # Validate JSON response before parsing
        if echo "$create_output" | jq empty 2>/dev/null; then
            local doc_status=$(echo "$create_output" | jq -r '.DocumentDescription.Status // "Unknown"')
            local doc_version=$(echo "$create_output" | jq -r '.DocumentDescription.DocumentVersion // "Unknown"')
            
            print_success "✅ Created: $SSM_DOC_DEBUG"
            print_info "Created with status: $doc_status, version: $doc_version"
        else
            print_success "✅ Document created (could not parse response)"
        fi
        
        # Wait for document to become active
        print_progress "Waiting for document to become active..."
        sleep 5
        
        # Verify document
        if verify_ssm_document "$SSM_DOC_DEBUG"; then
            print_success "Document is ready to use"
        else
            print_warning "Document created but verification failed - it may need more time to propagate"
        fi
        
        rm -f /tmp/ssm_create_error.txt
        return 0
    else
        local create_error=$(cat /tmp/ssm_create_error.txt 2>/dev/null || echo "Unknown error")
        print_error "❌ Failed to create: $SSM_DOC_DEBUG"
        print_error "Error: $create_error"
        
        # Check if it's a validation error
        if echo "$create_error" | grep -q "ValidationException"; then
            print_error "Document has validation errors. Please check the JSON structure."
            print_info "Document file: $doc_file"
            print_info "You can validate it with: jq . $doc_file"
        fi
        
        rm -f /tmp/ssm_create_error.txt
        return 1
    fi
}

# Function to download installers
download_installers() {
    local instance_id="$1"
    
    print_info "📦 Downloading installers from S3..."
    
    # First verify the document exists and is active
    if ! verify_ssm_document "$SSM_DOC_DEBUG"; then
        print_error "SSM document not ready. Please run with --register-document first"
        return 1
    fi
    
    # Prepare parameters for SSM document
    local keys_json=$(printf '%s\n' "${SOFTWARE_KEYS[@]}" | jq -R . | jq -s -c .)
    local names_json=$(printf '%s\n' "${SOFTWARE_NAMES[@]}" | jq -R . | jq -s -c .)
    local destinations_json=$(printf '%s\n' "${SOFTWARE_DESTINATIONS[@]}" | jq -R . | jq -s -c .)
    
    # Debug: Print parameter values
    print_info "Parameters being sent:"
    print_info "  S3BucketArn: $S3_ACCESS_POINT_ARN"
    print_info "  SoftwareKeys: $keys_json"
    print_info "  SoftwareNames: $names_json"
    print_info "  DownloadPaths: $destinations_json"
    print_info "  Region: $AWS_REGION"
    
    # Execute download SSM document
    print_progress "Executing download command..."
    
    local send_output=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "$SSM_DOC_DEBUG" \
        --parameters "{
            \"s3BucketArn\": [\"$S3_ACCESS_POINT_ARN\"],
            \"softwareKeys\": $keys_json,
            \"softwareNames\": $names_json,
            \"downloadPaths\": $destinations_json,
            \"region\": [\"$AWS_REGION\"]
        }" \
        --timeout-seconds 1800 \
        --region "$AWS_REGION" \
        --output json 2>&1)
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to send download command"
        print_error "Error output: $send_output"
        
        # Check for specific error types
        if echo "$send_output" | grep -q "InvalidDocument"; then
            print_error "The SSM document is invalid or not found"
            print_info "Try running: $0 --register-document"
        elif echo "$send_output" | grep -q "AccessDenied"; then
            print_error "Access denied. Check IAM permissions for SSM"
        elif echo "$send_output" | grep -q "InvalidInstanceId"; then
            print_error "Invalid instance ID: $instance_id"
        fi
        
        return 1
    fi
    
    local command_id=$(echo "$send_output" | jq -r '.Command.CommandId // ""')
    
    if [[ -z "$command_id" ]]; then
        print_error "Failed to get command ID from response"
        print_error "Response: $send_output"
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

# Function to monitor SSM command execution
monitor_command() {
    local instance_id="$1"
    local command_id="$2"
    local operation="$3"
    local max_wait=1800  # 30 minutes
    
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

# Function to check download status
check_download_status() {
    local instance_id="$1"
    
    print_info "Checking download status..."
    
    # Check for downloaded files
    local check_command=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters 'commands=[
            "$downloads = @()",
            "if (Test-Path \"C:\\downloads\\cmake\\cmake-4.1.1-windows-x86_64.msi\") { $downloads += \"CMake\" }",
            "if (Test-Path \"C:\\downloads\\git\\Git-2.51.0-64-bit.exe\") { $downloads += \"Git\" }",
            "if ($downloads.Count -eq 0) { \"No files downloaded\" } else { \"Downloaded: \" + ($downloads -join \", \") }"
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
        
        print_info "Download Status:"
        echo "$result"
    fi
}

# Function to validate S3 object (for individual mode)
validate_s3_object() {
    local s3_key="$1"
    local name="$2"
    
    print_progress "Validating S3 object: $name"
    
    # Check if object exists
    if aws s3api head-object \
        --bucket "$S3_ACCESS_POINT_ARN" \
        --key "$s3_key" \
        --region "$AWS_REGION" &>/dev/null; then
        print_success "  ✅ $name - Object exists in S3"
        return 0
    else
        print_error "  ❌ $name - Object not found in S3"
        return 1
    fi
}

# Function to register a single SSM document (for individual mode)
register_ssm_document_individual() {
    local doc_name="$1"
    local doc_file="$2"
    
    print_info "Registering SSM document: $doc_name"
    
    local doc_path="$SSM_DOCS_DIR/$doc_file"
    
    if [[ ! -f "$doc_path" ]]; then
        print_error "SSM document file not found: $doc_path"
        return 1
    fi
    
    # Check if document exists and delete it for fresh start
    if aws ssm describe-document \
        --name "$doc_name" \
        --region "$AWS_REGION" &>/dev/null; then
        print_info "Document exists, deleting for fresh registration..."
        aws ssm delete-document \
            --name "$doc_name" \
            --region "$AWS_REGION" &>/dev/null || true
        sleep 2
    fi
    
    # Create new document
    if aws ssm create-document \
        --name "$doc_name" \
        --document-type "Command" \
        --content "file://$doc_path" \
        --document-format "JSON" \
        --region "$AWS_REGION" &>/dev/null; then
        print_success "✅ Registered: $doc_name"
        return 0
    else
        print_error "❌ Failed to register: $doc_name"
        return 1
    fi
}

# Function to execute SSM document for a single installer (individual mode)
execute_installer() {
    local instance_id="$1"
    local installer="$2"
    
    local name="${INSTALLER_CONFIGS[${installer}_name]}"
    local s3_key="${INSTALLER_CONFIGS[${installer}_key]}"
    local destination="${INSTALLER_CONFIGS[${installer}_destination]}"
    local doc_name="${INSTALLER_CONFIGS[${installer}_doc_name]}"
    
    print_info "📦 Installing $name..."
    
    # Execute SSM document
    local command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "$doc_name" \
        --parameters "{
            \"s3BucketArn\": [\"$S3_ACCESS_POINT_ARN\"],
            \"softwareKey\": [\"$s3_key\"],
            \"softwareName\": [\"$name\"],
            \"downloadPath\": [\"$destination\"],
            \"region\": [\"$AWS_REGION\"]
        }" \
        --timeout-seconds 1800 \
        --region "$AWS_REGION" \
        --output text \
        --query 'Command.CommandId' 2>/dev/null)
    
    if [[ -z "$command_id" ]]; then
        print_error "Failed to send command for $name"
        return 1
    fi
    
    print_info "Command ID for $name: $command_id"
    
    # Monitor execution
    if monitor_command_individual "$instance_id" "$command_id" "$name"; then
        print_success "✅ $name installed successfully"
        return 0
    else
        print_error "❌ $name installation failed"
        return 1
    fi
}

# Function to monitor SSM command execution (individual mode)
monitor_command_individual() {
    local instance_id="$1"
    local command_id="$2"
    local installer_name="$3"
    local max_wait=900  # 15 minutes per installer
    
    local elapsed=0
    local interval=10
    
    print_progress "⏳ Monitoring $installer_name installation..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        # Get command status
        local status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --region "$AWS_REGION" \
            --query 'Status' \
            --output text 2>/dev/null || echo "Unknown")
        
        case "$status" in
            Success)
                print_success "$installer_name installation completed"
                return 0
                ;;
            Failed|TimedOut|Cancelled)
                print_error "$installer_name installation failed with status: $status"
                
                # Get error details
                local error_output=$(aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --region "$AWS_REGION" \
                    --query 'StandardErrorContent' \
                    --output text 2>/dev/null || echo "No error details available")
                
                if [[ -n "$error_output" && "$error_output" != "No error details available" ]]; then
                    print_error "Error details: $error_output"
                fi
                return 1
                ;;
            InProgress|Pending)
                if [[ $((elapsed % 30)) -eq 0 && $elapsed -gt 0 ]]; then
                    print_info "Still installing $installer_name... ($((elapsed/60)) minutes elapsed)"
                fi
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_warning "Timeout waiting for $installer_name installation"
    return 1
}

# Function to list configured installers (individual mode)
list_installers() {
    print_info "Configured Installers (in installation order):"
    print_info "=============================================="
    
    local index=1
    for installer in "${INSTALLER_ORDER[@]}"; do
        local name="${INSTALLER_CONFIGS[${installer}_name]}"
        local key="${INSTALLER_CONFIGS[${installer}_key]}"
        local doc="${INSTALLER_CONFIGS[${installer}_doc_name]}"
        
        echo ""
        echo "  [$index] $name"
        echo "      S3 Key: $key"
        echo "      SSM Document: $doc"
        ((index++))
    done
    echo ""
}

# Function to check installation status (individual mode)
check_installation_status() {
    local instance_id="$1"
    
    print_info "Checking installation status on $instance_id..."
    
    for installer in "${INSTALLER_ORDER[@]}"; do
        local name="${INSTALLER_CONFIGS[${installer}_name]}"
        local destination="${INSTALLER_CONFIGS[${installer}_destination]}"
        
        print_progress "Checking $name..."
        
        # Check if installer file exists
        local check_command=$(aws ssm send-command \
            --instance-ids "$instance_id" \
            --document-name "AWS-RunPowerShellScript" \
            --parameters "commands=[\"if (Test-Path '$destination') { Get-ChildItem '$destination' | Select-Object Name, Length, CreationTime | ConvertTo-Json } else { Write-Host 'Not found' }\"]" \
            --region "$AWS_REGION" \
            --output text \
            --query 'Command.CommandId' 2>/dev/null)
        
        if [[ -n "$check_command" ]]; then
            sleep 5
            
            local result=$(aws ssm get-command-invocation \
                --command-id "$check_command" \
                --instance-id "$instance_id" \
                --region "$AWS_REGION" \
                --query 'StandardOutputContent' \
                --output text 2>/dev/null || echo "Check failed")
            
            if [[ "$result" == *"Not found"* || "$result" == "Check failed" ]]; then
                print_warning "  ⚠️  $name: Not installed"
            else
                print_success "  ✅ $name: Installed"
            fi
        fi
    done
}

# Main execution function
main() {
    local instance_id=""
    local action="download"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            --s3-arn)
                S3_ACCESS_POINT_ARN="$2"
                shift 2
                ;;
            --mode)
                EXECUTION_MODE="$2"
                if [[ "$EXECUTION_MODE" != "debug" && "$EXECUTION_MODE" != "individual" ]]; then
                    print_error "Invalid mode: $EXECUTION_MODE. Must be 'debug' or 'individual'"
                    exit 1
                fi
                shift 2
                ;;
            --parallel)
                SEQUENTIAL_EXECUTION=false
                shift
                ;;
            --continue-on-error)
                CONTINUE_ON_ERROR=true
                shift
                ;;
            --register-document)
                action="register"
                shift
                ;;
            --register-only)
                action="register_only"
                shift
                ;;
            --list-documents)
                action="list"
                shift
                ;;
            --list-installers)
                action="list_installers"
                shift
                ;;
            --verify-document)
                action="verify"
                shift
                ;;
            --status)
                action="status"
                shift
                ;;
            --cleanup)
                action="cleanup"
                shift
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
    
    print_info "🚀 S3 Installers Download Script"
    print_info "Region: $AWS_REGION"
    print_info "S3 Access Point: $S3_ACCESS_POINT_ARN"
    print_info "Execution Mode: $EXECUTION_MODE"
    
    if [[ "$EXECUTION_MODE" == "debug" ]]; then
        print_info "Software packages: ${#SOFTWARE_KEYS[@]}"
    else
        print_info "Software packages: ${#INSTALLER_ORDER[@]}"
    fi
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Check for required SSM document files based on mode
    if [[ "$action" == "register" ]] || [[ "$action" == "download" ]]; then
        if [[ "$EXECUTION_MODE" == "debug" ]]; then
            local doc_file="$SCRIPT_DIR/ssm_doc_download_cmake_debug.json"
            if [[ ! -f "$doc_file" ]]; then
                print_error "Required SSM document file not found: $doc_file"
                print_info "Please ensure ssm_doc_download_cmake_debug.json exists in the same directory as this script"
                print_info "Current directory: $SCRIPT_DIR"
                exit 1
            fi
        else
            # Check for individual SSM document files
            if [[ ! -d "$SSM_DOCS_DIR" ]]; then
                print_error "SSM documents directory not found: $SSM_DOCS_DIR"
                print_info "Please ensure the ssm/ directory exists with individual SSM document files"
                exit 1
            fi
        fi
    fi
    
    # Handle different actions
    if [[ "$action" == "register" ]]; then
        if [[ "$EXECUTION_MODE" == "debug" ]]; then
            register_ssm_document
        else
            # Register all individual SSM documents
            print_info "📋 Registering all individual SSM documents..."
            local registration_failed=false
            
            for installer in "${INSTALLER_ORDER[@]}"; do
                local doc_name="${INSTALLER_CONFIGS[${installer}_doc_name]}"
                local doc_file="${INSTALLER_CONFIGS[${installer}_doc_file]}"
                
                if ! register_ssm_document_individual "$doc_name" "$doc_file"; then
                    print_error "Failed to register $doc_name"
                    registration_failed=true
                    if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                        exit 1
                    fi
                fi
            done
            
            if [[ "$registration_failed" == true && "$CONTINUE_ON_ERROR" != true ]]; then
                print_error "Some SSM documents failed to register"
                exit 1
            fi
            
            print_success "✅ All SSM documents registered"
        fi
        exit $?
    fi
    
    if [[ "$action" == "register_only" ]]; then
        if [[ "$EXECUTION_MODE" == "individual" ]]; then
            # Register all individual SSM documents
            print_info "📋 Registering all individual SSM documents..."
            local registration_failed=false
            
            for installer in "${INSTALLER_ORDER[@]}"; do
                local doc_name="${INSTALLER_CONFIGS[${installer}_doc_name]}"
                local doc_file="${INSTALLER_CONFIGS[${installer}_doc_file]}"
                
                if ! register_ssm_document_individual "$doc_name" "$doc_file"; then
                    print_error "Failed to register $doc_name"
                    registration_failed=true
                    if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                        exit 1
                    fi
                fi
            done
            
            if [[ "$registration_failed" == true && "$CONTINUE_ON_ERROR" != true ]]; then
                print_error "Some SSM documents failed to register"
                exit 1
            fi
            
            print_success "✅ All SSM documents registered"
            print_info "Registration only mode - exiting"
        else
            print_error "register-only mode is only available in individual execution mode"
            exit 1
        fi
        exit 0
    fi
    
    if [[ "$action" == "list" ]]; then
        list_ssm_documents
        exit $?
    fi
    
    if [[ "$action" == "list_installers" ]]; then
        if [[ "$EXECUTION_MODE" == "individual" ]]; then
            list_installers
        else
            print_error "list-installers is only available in individual execution mode"
            exit 1
        fi
        exit $?
    fi
    
    if [[ "$action" == "verify" ]]; then
        if [[ "$EXECUTION_MODE" == "debug" ]]; then
            verify_ssm_document "$SSM_DOC_DEBUG"
        else
            print_error "verify-document is only available in debug execution mode"
            exit 1
        fi
        exit $?
    fi
    
    if [[ "$action" == "cleanup" ]]; then
        cleanup_ssm_documents
        exit $?
    fi
    
    # Validate instance ID for actions that need it
    if [[ -z "$instance_id" ]]; then
        print_error "Instance ID is required"
        show_usage
        exit 1
    fi
    
    # Validate instance
    if ! validate_instance "$instance_id"; then
        print_error "Instance validation failed"
        exit 1
    fi
    
    if [[ "$action" == "status" ]]; then
        if [[ "$EXECUTION_MODE" == "debug" ]]; then
            check_download_status "$instance_id"
        else
            check_installation_status "$instance_id"
        fi
        exit 0
    fi
    
    # Execute based on mode
    if [[ "$EXECUTION_MODE" == "debug" ]]; then
        # Debug mode - single document approach
        print_info "📋 Verifying SSM document..."
        if ! verify_ssm_document "$SSM_DOC_DEBUG"; then
            print_warning "SSM document not found or not active"
            print_info "Attempting to register document..."
            
            if ! register_ssm_document; then
                print_error "Failed to register SSM document"
                exit 1
            fi
        fi
        
        # Validate S3 objects
        print_info "📋 Validating S3 objects..."
        if ! validate_s3_objects; then
            print_error "S3 validation failed"
            exit 1
        fi
        
        # Download installers
        print_info "📥 Downloading installers..."
        if download_installers "$instance_id"; then
            print_success "✅ Downloads completed"
        else
            print_error "❌ Downloads failed"
            exit 1
        fi
        
        # Final status check
        print_info "📊 Final Status Check..."
        check_download_status "$instance_id"
        
        print_success "✅ Debug Multi-Installer Download workflow complete!"
    else
        # Individual mode - separate documents approach
        print_info "📋 Step 1: Registering SSM documents..."
        local registration_failed=false
        
        for installer in "${INSTALLER_ORDER[@]}"; do
            local doc_name="${INSTALLER_CONFIGS[${installer}_doc_name]}"
            local doc_file="${INSTALLER_CONFIGS[${installer}_doc_file]}"
            
            if ! register_ssm_document_individual "$doc_name" "$doc_file"; then
                print_error "Failed to register $doc_name"
                registration_failed=true
                if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                    exit 1
                fi
            fi
        done
        
        if [[ "$registration_failed" == true && "$CONTINUE_ON_ERROR" != true ]]; then
            print_error "Some SSM documents failed to register"
            exit 1
        fi
        
        print_success "✅ SSM documents registered"
        
        # Step 2: Validate S3 objects
        print_info "📋 Step 2: Validating S3 objects..."
        local validation_failed=false
        
        for installer in "${INSTALLER_ORDER[@]}"; do
            local name="${INSTALLER_CONFIGS[${installer}_name]}"
            local s3_key="${INSTALLER_CONFIGS[${installer}_key]}"
            
            if ! validate_s3_object "$s3_key" "$name"; then
                validation_failed=true
                if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                    exit 1
                fi
            fi
        done
        
        if [[ "$validation_failed" == true && "$CONTINUE_ON_ERROR" != true ]]; then
            print_error "Some S3 objects are missing"
            exit 1
        fi
        
        # Step 3: Install software
        print_info "📋 Step 3: Installing software..."
        
        if [[ "$SEQUENTIAL_EXECUTION" == true ]]; then
            print_info "Running sequential installation (starting with CMake)..."
            
            local overall_success=true
            for installer in "${INSTALLER_ORDER[@]}"; do
                if ! execute_installer "$instance_id" "$installer"; then
                    overall_success=false
                    if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                        print_error "Installation failed, stopping sequence"
                        exit 1
                    fi
                    print_warning "Continuing despite failure..."
                fi
            done
            
            if [[ "$overall_success" == true ]]; then
                print_success "✅ All installations completed successfully!"
            else
                print_warning "⚠️  Some installations failed"
            fi
        else
            print_info "Running parallel installation..."
            print_warning "Note: Parallel installation is not recommended for dependent software"
            
            # Launch all installations in background
            local pids=()
            for installer in "${INSTALLER_ORDER[@]}"; do
                execute_installer "$instance_id" "$installer" &
                pids+=($!)
            done
            
            # Wait for all to complete
            local overall_success=true
            for pid in "${pids[@]}"; do
                if ! wait $pid; then
                    overall_success=false
                fi
            done
            
            if [[ "$overall_success" == true ]]; then
                print_success "✅ All installations completed successfully!"
            else
                print_warning "⚠️  Some installations failed"
            fi
        fi
        
        # Final status check
        print_info "📊 Final Status Check..."
        check_installation_status "$instance_id"
        
        print_success "✅ Individual Installer Deployment workflow complete!"
    fi
    
    print_info "Log file: $LOG_FILE"
}

# Execute main function
main "$@"