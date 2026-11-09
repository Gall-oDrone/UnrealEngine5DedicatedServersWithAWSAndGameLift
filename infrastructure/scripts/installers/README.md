# Software Installers Management

This directory contains scripts and AWS Systems Manager (SSM) documents for automated software installation on Windows EC2 instances. The system supports downloading and installing essential development tools required for Unreal Engine 5 compilation.

## Files

### Scripts

- `setup_installers_bucket.sh` - Creates S3 bucket with organized folder structure for storing installers
- `download_s3_installers.sh` - Main script for downloading and installing software from S3 using SSM documents
- `debug_cmake_download.sh` - Simplified debugging script for CMake download testing

### SSM Documents

- `ssm_doc_download_s3_installers.json` - Master SSM document for batch installer downloads
- `ssm_doc_download_cmake.json` - Individual CMake installer document
- `ssm_doc_download_git.json` - Individual Git for Windows installer document
- `ssm_doc_download_nasm.json` - Individual NASM installer document
- `ssm_doc_download_nvidia_grid.json` - Individual NVIDIA GRID driver installer document
- `ssm_doc_download_python_manager.json` - Individual Python Manager installer document
- `ssm_doc_download_strawberry_perl.json` - Individual Strawberry Perl installer document
- `ssm_doc_download_visual_studio_2022.json` - Individual Visual Studio 2022 installer document

## Supported Software

The installer system supports the following software packages:

| Software | Version | Purpose |
|----------|---------|---------|
| **CMake** | 4.1.1 | Build system generator |
| **Git for Windows** | 2.51.0 | Version control system |
| **NASM** | 2.16.03 | Netwide Assembler for assembly code |
| **NVIDIA GRID Driver** | Latest | GPU drivers for visualization workloads |
| **Python Manager** | 25.0b14 | Python package management |
| **Strawberry Perl** | 5.40.2.1 | Perl interpreter for build scripts |
| **Visual Studio 2022** | 17.14.15 | C++ development environment |

## Installation Process

The installer system follows a structured approach:

### Step 1: S3 Bucket Setup
- Creates organized folder structure in S3
- Downloads installers from official sources
- Uploads installers to S3 with proper organization
- **Note**: NVIDIA GRID driver downloads directly from AWS S3 bucket

### Step 2: SSM Document Registration
- Registers SSM documents in AWS Systems Manager
- Supports both individual and batch installation modes
- Validates document syntax and permissions

### Step 3: Software Installation
- Downloads installers from S3 to Windows instances
- Downloads NVIDIA GRID driver from AWS S3 bucket
- Executes installation with proper parameters
- Monitors installation progress and handles errors

## Usage

### 1. Setup S3 Bucket

```bash
# Create S3 bucket with installer structure
./setup_installers_bucket.sh

# Create bucket in specific region
./setup_installers_bucket.sh --region us-west-2

# List bucket contents after creation
./setup_installers_bucket.sh --list
```

### 2. Download and Install Software

#### Debug Mode (Single Document)
```bash
# Download all software using single SSM document
./download_s3_installers.sh i-0abc123def456789

# Register SSM document first
./download_s3_installers.sh --register-document

# Check download status
./download_s3_installers.sh --status i-0abc123def456789
```

#### Individual Mode (Separate Documents)
```bash
# Install all software using separate SSM documents
./download_s3_installers.sh --mode individual i-0abc123def456789

# Install in parallel (not recommended for dependent software)
./download_s3_installers.sh --mode individual --parallel i-0abc123def456789

# Register individual SSM documents only
./download_s3_installers.sh --mode individual --register-only

# List configured installers
./download_s3_installers.sh --mode individual --list-installers
```

### 3. Debug CMake Download

```bash
# Debug CMake download specifically
./debug_cmake_download.sh i-0abc123def456789

# Register debug SSM document
./debug_cmake_download.sh --register-document

# Check CMake download status
./debug_cmake_download.sh --status i-0abc123def456789
```

## Configuration

### Environment Variables

```bash
# AWS Configuration
export AWS_REGION="us-east-1"
export S3_ACCESS_POINT_ARN="arn:aws:s3:us-east-1:326105557351:accesspoint/test-ap-2"

# S3 Bucket Configuration
export BUCKET_NAME="installers-1757543545-28881"
```

### S3 Folder Structure

```
installers-bucket/
├── CMake/
│   └── Windows x86_64/
│       └── Version 4.1.1/
│           └── cmake-4.1.1-windows-x86_64.msi
├── Git/
│   └── Windows x86_64/
│       └── Version 2.51.0/
│           └── Git-2.51.0-64-bit.exe
├── NASM/
│   └── Windows x86_64/
│       └── Version 2.16.03/
│           └── nasm-2.16.03-installer-x64.exe
├── Python Manager/
│   └── Windows x86_64/
│       └── Version 25.0b14/
│           └── python-manager-25.0b14.msi
├── Strawberry Perl/
│   └── Windows x86_64/
│       └── Version 5.40.2.1/
│           └── strawberry-perl-5.40.2.1-64bit.msi
└── Visual Studio 2022/
    └── Visual Studio 2022 v17.14.15/
        └── Community Edition/
            └── VisualStudioSetup.exe
```

**Note**: NVIDIA GRID driver is downloaded directly from the AWS S3 bucket `ec2-windows-nvidia-drivers` and does not require the local S3 bucket setup.

## Prerequisites

### Local Machine
- **AWS CLI** installed and configured
- **jq** for JSON processing
- **curl** for downloading installers
- **bash** shell environment

### EC2 Instance
- **Windows Server 2022** or compatible
- **SSM Agent** installed and running
- **Internet access** for downloading dependencies
- **Administrator privileges** for software installation

### AWS Permissions
- **S3** read access to installer bucket and AWS NVIDIA drivers bucket
- **SSM** document registration and execution permissions
- **EC2** instance management permissions

## Installation Destinations

Software is installed to the following locations on Windows instances:

| Software | Installation Path |
|----------|------------------|
| CMake | `C:\Program Files\CMake\` |
| Git | `C:\Program Files\Git\` |
| NASM | `C:\Program Files\NASM\` |
| NVIDIA GRID Driver | `C:\Users\Public\Desktop\NVIDIA\` (download location) |
| Python Manager | `C:\Program Files\Python Manager\` |
| Strawberry Perl | `C:\Strawberry\` |
| Visual Studio 2022 | `C:\Program Files\Microsoft Visual Studio\` |

## Monitoring and Logging

### Log Files
- **Main Script**: `logs/installer_deployment_YYYYMMDD_HHMMSS.log`
- **Debug Script**: `cmake_debug_YYYYMMDD_HHMMSS.log`
- **SSM Execution**: Available in AWS Systems Manager console

### Status Monitoring
```bash
# Check installation status
./download_s3_installers.sh --status i-0abc123def456789

# List SSM documents
./download_s3_installers.sh --list-documents

# Verify document readiness
./download_s3_installers.sh --verify-document
```

## Troubleshooting

### Common Issues

1. **SSM Agent Not Online**
   - Ensure SSM Agent is installed and running
   - Check IAM role has SSM permissions
   - Verify security group allows SSM traffic

2. **S3 Access Denied**
   - Verify S3 bucket permissions
   - Check S3 Access Point configuration
   - Ensure IAM role has S3 read access

3. **Installation Failures**
   - Check Windows instance has sufficient disk space
   - Verify installer files are not corrupted
   - Review SSM execution logs for detailed errors

4. **Document Registration Failures**
   - Validate JSON syntax in SSM documents
   - Check AWS CLI permissions
   - Ensure document names are unique

5. **NVIDIA GRID Driver Issues**
   - Verify instance has compatible GPU (G3, G4dn, G5, G6, etc.)
   - Check AWS S3 bucket access permissions for `ec2-windows-nvidia-drivers`
   - Ensure Windows instance has sufficient disk space for driver files
   - Verify driver files downloaded to `C:\Users\Public\Desktop\NVIDIA\`

### Debug Commands

```bash
# Clean up all SSM documents
./download_s3_installers.sh --cleanup

# Validate S3 objects
aws s3api head-object --bucket "$S3_ACCESS_POINT_ARN" --key "CMake/Windows x86_64/Version 4.1.1/cmake-4.1.1-windows-x86_64.msi"

# Check SSM agent status
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-0abc123def456789"

# Check NVIDIA GRID driver download status
aws ssm send-command --instance-ids "i-0abc123def456789" --document-name "AWS-RunPowerShellScript" --parameters 'commands=["if (Test-Path \"C:\\Users\\Public\\Desktop\\NVIDIA\") { Get-ChildItem \"C:\\Users\\Public\\Desktop\\NVIDIA\" | Select-Object Name, Length, CreationTime } else { Write-Host \"NVIDIA folder not found\" }"]'
```

## Integration with Unreal Engine

This installer system is designed to prepare Windows EC2 instances for Unreal Engine 5 compilation by installing:

- **Build Tools**: CMake, Visual Studio 2022 for C++ compilation
- **Version Control**: Git for source code management
- **Scripting**: Perl and Python for build automation
- **Assembler**: NASM for low-level code compilation
- **GPU Drivers**: NVIDIA GRID drivers for GPU-accelerated workloads

The installed software provides the complete development environment needed for compiling Unreal Engine 5 dedicated servers, including GPU support for visualization and compute workloads.

## NVIDIA GRID Driver Details

The NVIDIA GRID driver installer provides GPU support for Windows EC2 instances with NVIDIA GPUs. This is particularly useful for:

### Supported Instance Types
- **G3**: M60 GPU instances
- **G4dn**: T4 GPU instances  
- **G5**: A10 GPU instances
- **G6**: L4 GPU instances
- **G6e**: L40S GPU instances
- **G6f**: L4 GPU instances (GRID only)
- **Gr6**: L4 GPU instances
- **Gr6f**: L4 GPU instances (GRID only)

### Driver Features
- **Professional Visualization**: Optimized for 3D rendering and video processing
- **Quadro Virtual Workstations**: Support for up to 4 4K displays per GPU
- **GRID vApps**: Remote Desktop Session Host (RDSH) capabilities
- **CUDA Support**: Full CUDA toolkit compatibility for compute workloads

### Installation Process
1. Downloads latest NVIDIA GRID driver from AWS S3 bucket `ec2-windows-nvidia-drivers`
2. Saves driver files to `C:\Users\Public\Desktop\NVIDIA\`
3. Requires manual installation after download
4. Supports both Tesla and GRID driver modes

### Post-Installation
After the driver files are downloaded, you'll need to:
1. Navigate to the NVIDIA folder on the desktop
2. Run the appropriate installer for your Windows version
3. Follow the installation wizard
4. Reboot the instance as required

For more information, see the [AWS NVIDIA Driver Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/install-nvidia-driver.html#nvidia-GRID-driver).

## Security Considerations

- **S3 Access**: Uses S3 Access Points for controlled access
- **IAM Roles**: Follows least privilege principle
- **Network Security**: Requires proper security group configuration
- **Logging**: Comprehensive audit trail of all operations

## References

- [AWS Systems Manager Documents](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-ssm-docs.html)
- [S3 Access Points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points.html)
- [Unreal Engine Build Requirements](https://docs.unrealengine.com/5.4/en-US/building-unreal-engine-from-source/)
- [Windows Development Environment Setup](https://docs.microsoft.com/en-us/cpp/build/building-on-the-command-line)
