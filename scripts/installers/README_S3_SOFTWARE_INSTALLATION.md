# S3 Software Installation System

A comprehensive system for downloading and installing software from S3 to Windows EC2 instances using AWS Systems Manager (SSM).

## 📋 Overview

This system provides an orchestrated approach to:
1. **Validate** S3 objects exist and are accessible
2. **Download** software installers from S3 access points
3. **Install** MSI and EXE packages with proper error handling
4. **Monitor** the entire process with detailed logging

## 🏗️ Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌───────────────┐
│  Controller     │────▶│  SSM         │────▶│  Windows      │
│  Bash Script    │     │  Documents   │     │  Instance     │
└─────────────────┘     └──────────────┘     └───────────────┘
        │                      │                      │
        │                      ├── Download Doc       ├── Downloads
        │                      ├── MSI Install Doc    ├── Installs
        │                      └── EXE Install Doc    └── Logs
        │
        └── Orchestrates entire workflow
```

## 📦 Components

### 1. Controller Script (`install_s3_software.sh`)
- **Purpose**: Main orchestration script that manages the entire workflow
- **Features**:
  - S3 object validation
  - SSM document registration
  - Phased execution (validate → download → install)
  - Progress monitoring
  - State management
  - Comprehensive logging

### 2. SSM Documents
These JSON documents define the commands executed on the Windows instance:

#### a. `ssm_doc_download_s3_installers.json`
- Downloads multiple installers from S3 in a single operation
- Handles AWS CLI operations
- Creates download manifest
- Supports parallel downloads (optional)

#### b. `ssm_doc_install_msi.json`
- Installs MSI packages with proper error handling
- Interprets MSI exit codes
- Creates detailed installation logs
- Verifies installation success

#### c. `ssm_doc_install_exe.json`
- Installs EXE packages with installer type detection
- Supports NSIS, InnoSetup, InstallShield, and generic installers
- Intelligent argument handling based on installer type
- Digital signature verification

## 🚀 Quick Start

### Prerequisites
1. AWS CLI configured with appropriate permissions
2. SSM Agent running on target Windows instance
3. S3 access configured for the instance IAM role
4. `jq` installed for JSON parsing

### Step 1: Register SSM Documents

```bash
# Register all SSM documents in AWS
./install_s3_software.sh --register-documents
```

### Step 2: Configure Software List

Edit the arrays in `install_s3_software.sh`:

```bash
declare -a SOFTWARE_KEYS=(
    "CMake/Windows x86_64/Version 4.1.1/cmake-4.1.1-windows-x86_64.msi"
    "Git/Windows x86_64/Version 2.51.0/Git-2.51.0-64-bit.exe"
    # Add more software keys...
)

declare -a SOFTWARE_NAMES=(
    "CMake"
    "Git for Windows"
    # Add corresponding names...
)
```

### Step 3: Run Installation

```bash
# Full installation workflow
./install_s3_software.sh i-0abc123def456789

# Dry run (validation only)
./install_s3_software.sh -d i-0abc123def456789

# Skip validation
./install_s3_software.sh --skip-validation i-0abc123def456789

# Download only (no installation)
./install_s3_software.sh --skip-install i-0abc123def456789
```

## 📊 Usage Examples

### List Configured Software
```bash
./install_s3_software.sh -l
```

### Check Installation Status
```bash
./install_s3_software.sh -s i-0abc123def456789
```

### Auto-approve Installation
```bash
./install_s3_software.sh -a i-0abc123def456789
```

### Parallel Downloads (Faster)
```bash
./install_s3_software.sh -p i-0abc123def456789
```

## 🔧 Configuration

### S3 Access Point
Configure in `install_s3_software.sh`:
```bash
S3_ACCESS_POINT_ARN="arn:aws:s3:us-east-1:326105557351:accesspoint/test-ap-2"
```

### Software Configuration
Each software package requires:
- **S3 Key**: Full path in S3 bucket
- **Name**: Descriptive name for logging
- **Type**: `msi` or `exe`
- **Arguments**: Silent installation parameters
- **Destination**: Installation directory

Example:
```bash
SOFTWARE_KEYS[0]="CMake/Windows x86_64/Version 4.1.1/cmake-4.1.1-windows-x86_64.msi"
SOFTWARE_NAMES[0]="CMake"
SOFTWARE_TYPES[0]="msi"
SOFTWARE_ARGS[0]="/quiet /norestart"
SOFTWARE_DESTINATIONS[0]="C:\\cmake"
```

## 📝 Logging

### Log Locations

#### On Controller Machine
- Main log: `./s3_software_install_YYYYMMDD_HHMMSS.log`
- State file: `./installation_state.json`

#### On Windows Instance
- Download logs: `C:\logs\s3-download-*.log`
- Installation logs: `C:\logs\<software>-install-*.log`
- MSI logs: `C:\logs\<software>-msi-*.log`
- Progress files: `C:\logs\download-progress.txt`
- Download manifest: `C:\logs\download-manifest-*.json`

### Log Levels
- **INFO**: General information
- **SUCCESS**: Successful operations
- **WARNING**: Non-critical issues
- **ERROR**: Failures requiring attention

## 🔍 Monitoring

### Real-time Progress
The script provides real-time status updates:
```
[INFO] 📋 Phase 1: Validating S3 objects...
[PROGRESS] Checking: CMake
[SUCCESS]   ✅ CMake - Valid (85MB, Modified: 2024-01-15)
[INFO] 📥 Phase 2: Downloading installers...
[PROGRESS] Status: InProgress
[INFO] 🔧 Phase 3: Installing software...
[SUCCESS]   ✅ CMake installed successfully
```

### State Management
The system maintains state in `installation_state.json`:
```json
{
    "instance_id": "i-0abc123def456789",
    "phase": "install",
    "status": "completed",
    "timestamp": "2024-01-15T10:30:00Z",
    "software_count": 5
}
```

## 🚨 Troubleshooting

### Common Issues

#### 1. S3 Access Denied
```bash
# Check IAM role permissions
aws iam get-role-policy --role-name <instance-role>
```

#### 2. SSM Agent Not Online
```bash
# Verify SSM agent status
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=<instance-id>"
```

#### 3. Installation Failures
```bash
# Check detailed logs on instance
./install_s3_software.sh -s i-0abc123def456789
```

#### 4. Download Failures
- Verify S3 object exists
- Check network connectivity
- Ensure sufficient disk space

### Debug Mode
Enable verbose logging in PowerShell scripts by modifying SSM documents:
```json
"Write-Log \"  Executing: $awsCommand\" \"DEBUG\""
```

## 🔐 Security Considerations

1. **IAM Permissions**: Instances need:
   - S3 read access to the access point
   - SSM managed instance core policy
   
2. **Network Security**:
   - Ensure outbound HTTPS (443) is allowed
   - S3 endpoint connectivity required
   
3. **Software Verification**:
   - Digital signature checking for EXE files
   - File size validation
   - Hash verification (optional, can be added)

## 📈 Performance Optimization

### Parallel Downloads
Enable for faster downloads of multiple files:
```bash
./install_s3_software.sh -p i-0abc123def456789
```

### Instance Type
Use instances with better network performance:
- `c5.large` or larger recommended
- Enhanced networking enabled

### S3 Transfer
- Use S3 Transfer Acceleration if available
- Consider VPC endpoints for S3

## 🔄 Maintenance

### Update Software List
1. Edit arrays in `install_s3_software.sh`
2. Upload new software to S3
3. Run validation: `./install_s3_software.sh -d <instance-id>`

### Clean Up Logs
```bash
# Clean up old logs (keeps last 10)
./install_s3_software.sh -c
```

### Update SSM Documents
```bash
# After modifying JSON files
./install_s3_software.sh --register-documents
```

## 📚 Additional Resources

- [AWS Systems Manager Documentation](https://docs.aws.amazon.com/systems-manager/)
- [S3 Access Points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points.html)
- [PowerShell MSI Installation](https://docs.microsoft.com/en-us/powershell/scripting/samples/working-with-software-installations)

## 🤝 Contributing

To add support for new software:
1. Add S3 key to `SOFTWARE_KEYS` array
2. Add corresponding entries to other arrays
3. Test with dry run first
4. Document any special installation requirements

## 📄 License

This system is provided as-is for use with AWS infrastructure.