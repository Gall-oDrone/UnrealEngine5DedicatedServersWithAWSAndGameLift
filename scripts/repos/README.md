# OpenSSL Build SSM Document

This directory contains AWS Systems Manager (SSM) documents for building OpenSSL from source on Windows EC2 instances.

## Files

- `ssm_doc_build_openssl.json` - SSM document that builds OpenSSL following the official Windows build steps
- `deploy_openssl_ssm_doc.sh` - Script to deploy the SSM document to AWS
- `README.md` - This documentation file

## OpenSSL Build Process

The SSM document follows the official OpenSSL Windows build steps from [NOTES-WINDOWS.md](https://github.com/openssl/openssl/blob/master/NOTES-WINDOWS.md):

### Step 1: Repository Check
- Verifies that the OpenSSL repository is cloned and accessible
- Checks for the presence of the source code

### Step 2: Build Tools Verification
- Checks for Visual Studio Build Tools (using vswhere.exe)
- Verifies Perl installation (required for OpenSSL build)
- Verifies NASM installation (required for assembly code)

### Step 3: Visual Studio Environment Setup
- Sets up the Visual Studio build environment using `vcvarsall.bat`
- Configures environment variables for the target architecture
- Supports x86, x64, ARM, and ARM64 architectures

### Step 4: OpenSSL Configuration
- Runs `perl Configure VC-WIN64A` (or appropriate variant)
- Configures build options based on architecture and build type
- Sets installation paths and SSL directory

### Step 5: Build Process
- Executes `nmake` to build OpenSSL
- Handles build errors and provides detailed logging
- Supports both Release and Debug builds

### Step 6: Testing and Installation
- Runs `nmake test` to verify the build
- Executes `nmake install` to install OpenSSL
- Verifies installation and reports file sizes

## Prerequisites

Before running the OpenSSL build, ensure the following are installed on the Windows EC2 instance:

1. **Visual Studio Build Tools** or **Visual Studio Community/Professional**
   - Required for C/C++ compilation
   - Must include MSVC compiler and Windows SDK

2. **Perl**
   - Strawberry Perl or ActivePerl
   - Required for OpenSSL configuration scripts

3. **NASM (Netwide Assembler)**
   - Required for assembly code compilation
   - Download from: https://www.nasm.us/

4. **Git**
   - Required for cloning the OpenSSL repository
   - Should be installed via the repository deployment script

## Usage

### 1. Deploy the SSM Document

```bash
# Deploy with default settings
./deploy_openssl_ssm_doc.sh

# Deploy to specific environment and region
./deploy_openssl_ssm_doc.sh -e prod -r us-west-2

# Update existing document
./deploy_openssl_ssm_doc.sh --update

# Validate JSON syntax only
./deploy_openssl_ssm_doc.sh --validate
```

### 2. Clone OpenSSL Repository

First, ensure the OpenSSL repository is cloned using the repository deployment script:

```bash
# From the repos directory
./deploy_repos_staged.sh <instance-id>
```

This will clone the OpenSSL repository to `D:\UnrealEngine\OpenSSL`.

### 3. Execute the Build

Use AWS Systems Manager to execute the document on your Windows EC2 instance:

```bash
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "OpenSSL-Build-Windows" \
    --parameters '{
        "opensslRepoPath": ["D:\\UnrealEngine\\OpenSSL"],
        "buildType": ["Release"],
        "architecture": ["x64"],
        "installPath": ["C:\\OpenSSL"]
    }' \
    --region us-east-1
```

## Parameters

The SSM document accepts the following parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `opensslRepoPath` | String | `D:\UnrealEngine\OpenSSL` | Path to the cloned OpenSSL repository |
| `buildType` | String | `Release` | Build type: `Release` or `Debug` |
| `architecture` | String | `x64` | Target architecture: `x86`, `x64`, `ARM`, `ARM64` |
| `installPath` | String | `C:\OpenSSL` | Installation path for OpenSSL |
| `region` | String | `us-east-1` | AWS region |

## Build Output

The build process will:

1. **Install OpenSSL** to the specified installation path
2. **Create logs** in `C:\logs\openssl-build-YYYYMMDD-HHMMSS.log`
3. **Report success/failure** with detailed error messages
4. **Verify installation** and report file sizes

## Troubleshooting

### Common Issues

1. **Visual Studio Build Tools Not Found**
   - Ensure Visual Studio Build Tools are installed
   - Check that vswhere.exe is available in the expected location

2. **Perl Not Found**
   - Install Strawberry Perl or ActivePerl
   - Ensure Perl is in the system PATH

3. **NASM Not Found**
   - Download and install NASM from https://www.nasm.us/
   - Ensure NASM is in the system PATH

4. **Repository Not Found**
   - Ensure the OpenSSL repository is cloned first
   - Check the repository path parameter

5. **Build Failures**
   - Check the detailed log file in `C:\logs\`
   - Verify all prerequisites are installed
   - Ensure sufficient disk space is available

### Log Files

All build operations are logged to:
- `C:\logs\openssl-build-YYYYMMDD-HHMMSS.log`

The log file contains:
- Parameter values
- Build tool verification results
- Configuration output
- Build progress and errors
- Installation verification

## Integration with Unreal Engine

This OpenSSL build is designed to work with Unreal Engine 5 dedicated servers. The built OpenSSL libraries can be used for:

- SSL/TLS connections in game servers
- Secure communication with AWS services
- Cryptographic operations
- HTTPS client/server functionality

## References

- [OpenSSL Windows Build Notes](https://github.com/openssl/openssl/blob/master/NOTES-WINDOWS.md)
- [Microsoft C++ Build Tools](https://learn.microsoft.com/en-us/cpp/build/building-on-the-command-line)
- [AWS Systems Manager Documents](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-ssm-docs.html)
