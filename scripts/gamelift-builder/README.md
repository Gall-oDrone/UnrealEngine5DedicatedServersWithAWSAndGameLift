# Unreal Engine Builder Upload to S3

This directory contains scripts for uploading Unreal Engine builders to an S3 bucket using AWS Systems Manager (SSM).

## 🎉 Recent Updates

**Major improvements have been made to fix critical issues and add new features:**

### ✅ Fixed Issues
1. **Silent Failure Bug**: Script no longer stops silently after validation - now continues through to upload
2. **Instance Targeting**: Removed unreliable tag-based targeting; now requires explicit instance ID
3. **Real-time Monitoring**: Added progress monitoring with live status updates
4. **PowerShell Syntax Error**: Fixed quote escaping in SSM document that caused upload failures
5. **Error Handling**: Enhanced error messages and validation at every step

### 🚀 New Features
1. **Automatic Version Management**: SSM document automatically creates new versions on each run
2. **Cleanup Utility**: New `--clean` flag to delete SSM document and all versions
3. **Instance Validation**: Pre-flight checks for instance state and SSM agent status
4. **Enhanced Logging**: Better output with version numbers and detailed status

**The script is now production-ready with full error handling and monitoring!**

## Files

- `upload_builders_to_s3.sh` - Main bash script for uploading UE builders to S3
- `ssm/ssm_doc_upload_ue_builders.json` - SSM document for performing the actual upload operations
- `README.md` - This documentation file
- `VERSION_MANAGEMENT.md` - Detailed guide on version management features

## Quick Start

```bash
# 1. Find your Windows EC2 instance with the builders
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# 2. Edit the script to configure your builder paths
nano upload_builders_to_s3.sh
# Update BUILDER_PATHS, BUILDER_NAMES, and BUILDER_S3_KEYS arrays

# 3. Run the upload
./upload_builders_to_s3.sh --instance-id i-YOUR-INSTANCE-ID

# 4. Verify upload
aws s3 ls s3://ue-builders-default/builders/ --recursive --human-readable
```

## Prerequisites

1. **AWS CLI installed and configured**
   - Install AWS CLI v2
   - Configure with appropriate credentials (`aws configure`)

2. **IAM Permissions**
   - The script needs permissions to:
     - Create/manage S3 buckets
     - Create/update SSM documents
     - Execute SSM commands
     - Describe EC2 instances
     - Describe SSM instance information
   - Target instances need permissions to:
     - Read from local filesystem
     - Write to the specified S3 bucket

3. **Target Instance**
   - Must be running with SSM Agent installed and active
   - Must have AWS CLI installed (at `C:\Program Files\Amazon\AWSCLIV2\aws.exe` on Windows)
   - Must have appropriate IAM role attached with S3 write permissions
   - Must be accessible via SSM (ping status: Online)
   - Builder directories must exist at the configured paths

## Usage

### Configuration

Before running the script, configure your builder paths in the script arrays:

```bash
# Edit the script to configure your builders
nano upload_builders_to_s3.sh

# Update these arrays:
declare -a BUILDER_PATHS=(
    "D:\\UE_5_6_Projects\\...\\FPSTemplate"
    "D:\\UE_5_6_Projects\\...\\AnotherBuilder"
)

declare -a BUILDER_NAMES=(
    "Binaries.zip"
    "AnotherBuilder.zip"
)

declare -a BUILDER_S3_KEYS=(
    "builders/Windows/Server/FPSTemplate_Server/"
    "builders/Windows/Server/AnotherBuilder/"
)
```

### Basic Usage

**IMPORTANT:** You MUST provide an instance ID where the builders are located.

```bash
# Upload all configured builders to a specific instance
./upload_builders_to_s3.sh --instance-id i-1234567890abcdef0

# Show current configuration
./upload_builders_to_s3.sh --show-config
```

### Advanced Usage

```bash
# Specify instance ID, custom bucket name and region
./upload_builders_to_s3.sh \
  --instance-id i-1234567890abcdef0 \
  --bucket my-ue-builders \
  --region us-west-2

# Use environment variables
INSTANCE_ID=i-1234567890abcdef0 \
BUCKET_NAME=my-custom-bucket \
AWS_REGION=eu-west-1 \
./upload_builders_to_s3.sh

# Dry run to see what would be done
./upload_builders_to_s3.sh \
  --instance-id i-1234567890abcdef0 \
  --dry-run

# List bucket contents after upload
./upload_builders_to_s3.sh \
  --instance-id i-1234567890abcdef0 \
  --list
```

### Command Line Options

- `-h, --help` - Show help message
- `-i, --instance-id` - **REQUIRED** EC2 instance ID where builders are located (not needed for `--clean`)
- `-b, --bucket` - Specify S3 bucket name (default: ue-builders-default)
- `-r, --region` - Specify AWS region (default: us-east-1)
- `-l, --list` - List bucket contents after upload
- `--dry-run` - Show what would be done without executing
- `--show-config` - Show current builder configuration
- `--clean` or `--delete-document` - Delete the SSM document and all its versions

### Environment Variables

- `INSTANCE_ID` - EC2 instance ID (overrides `-i` option)
- `BUCKET_NAME` - S3 bucket name (overrides `-b` option)
- `AWS_REGION` - AWS region (overrides `-r` option)

## How It Works

1. **Instance Validation**: Validates the target instance is running and SSM agent is online
2. **AWS Validation**: Validates AWS CLI installation and credentials
3. **Bucket Creation**: Creates the S3 bucket if it doesn't exist
4. **Builder Validation**: Validates builder configuration
5. **SSM Document**: Creates or updates an SSM document for uploading builders
   - **Automatic Versioning**: Every run creates a new document version
   - The new version is automatically set as the default
   - Old versions are retained for audit/rollback purposes
6. **Execution**: Executes the SSM document on the target instance to perform the actual upload
7. **Monitoring**: Monitors the upload progress in real-time and displays results

## Expected Output

When you run the script, you'll see detailed progress at each step:

```
Unreal Engine Builder Upload to S3
===================================
Instance ID: i-046347dd7fd40902e
Bucket name: ue-builders-default
AWS region: us-east-1
Configured builders: 1

Current Builder Configuration:
==============================
Instance ID: i-046347dd7fd40902e
Bucket Name: ue-builders-default
AWS Region: us-east-1
SSM Document: UploadUEBuildersToS3
Total Builders: 1

Configured Builders:
--------------------
Builder 1:
  Name: Binaries.zip
  Path: D:/UE_5_6_Projects/.../FPSTemplate
  S3 Key: builders/Windows/Server/FPSTemplate/

Validating instance ID: i-046347dd7fd40902e
Instance state: running
Checking SSM agent connectivity...
✓ SSM agent status: Online
✓ Instance validation successful

Checking if S3 bucket exists: ue-builders-default
Bucket 'ue-builders-default' already exists.

Validating builder paths...
Checking builder 1: Binaries.zip
  Path: D:/UE_5_6_Projects/.../FPSTemplate
  ✓ Path configured (validation will occur on target instance)
Builder configuration validation complete: 1 builders configured

Preparing SSM document: UploadUEBuildersToS3
SSM document template found: /path/to/ssm_doc_upload_ue_builders.json
SSM document exists - creating new version...
✓ SSM document updated successfully
  New version: 3
  Setting version 3 as default...
  ✓ Default version updated to 3
SSM document 'UploadUEBuildersToS3' ready.

Executing builder uploads...
Processing builder 1/1...
Uploading builder 1: Binaries.zip
  Local Path: D:/UE_5_6_Projects/.../FPSTemplate
  S3 Key: builders/Windows/Server/FPSTemplate/
  Target Instance: i-046347dd7fd40902e
  ✅ SSM command sent successfully
  Command ID: abc-123-def-456

Monitoring upload progress for: Binaries.zip
Command ID: abc-123-def-456
This may take several minutes depending on builder size...

  ✅ Upload completed successfully!

Upload Summary:
===============
Total builders: 1
Successful initiations: 1
Failed initiations: 0

✅ All builder uploads initiated successfully!

Upload process completed!
Bucket URL: https://s3.console.aws.amazon.com/s3/buckets/ue-builders-default
```

## SSM Document Versioning

The script automatically manages SSM document versions:

- **First Run**: Creates the SSM document (version 1)
- **Subsequent Runs**: Creates a new version and sets it as default
- **Version History**: All versions are retained in AWS SSM
- **Cleanup**: Use `--clean` to delete the document and all versions

**Why Versioning?**
- Always uses the latest version of the upload logic
- Maintains audit trail of all changes
- Enables rollback if needed
- Fixed bugs are automatically deployed on next run

### Managing SSM Document Versions

```bash
# View all versions of the SSM document
aws ssm list-document-versions \
  --name "UploadUEBuildersToS3" \
  --region us-east-1

# Get details of a specific version
aws ssm describe-document \
  --name "UploadUEBuildersToS3" \
  --document-version "2" \
  --region us-east-1

# Delete the SSM document and all versions
./upload_builders_to_s3.sh --clean
```

## S3 Bucket Structure

Builders are uploaded to S3 with the following structure:

```
s3://your-bucket-name/
├── builders/
│   ├── builder-name-1/
│   │   ├── (builder files and folders)
│   │   └── ...
│   ├── builder-name-2/
│   │   ├── (builder files and folders)
│   │   └── ...
│   └── ...
```

## SSM Document Details

The SSM document (`ssm_doc_upload_ue_builders.json`) performs the following operations:

1. **Validation**: Checks AWS CLI, credentials, and S3 bucket access
2. **Directory Sync**: Uses `aws s3 sync` to upload entire builder directories
3. **Logging**: Comprehensive logging to `C:\logs\ue-builder-upload-<timestamp>.log`
4. **Progress Tracking**: Reports upload progress, file sizes, and duration
5. **Error Handling**: Graceful error handling with detailed error messages

## Monitoring Uploads

The script now monitors upload progress in real-time. You'll see:
- Upload initiation confirmation
- Progress indicators during upload
- Success or failure status
- Command output including any errors

If the monitoring times out, you can check status manually:

```bash
# Get execution status
aws ssm get-command-invocation \
  --command-id <command-id> \
  --instance-id <instance-id>

# List all command executions
aws ssm list-command-invocations --command-id <command-id>
```

## Troubleshooting

### Common Issues

1. **"No instance ID provided"**
   - **Solution**: You must specify an instance ID using `-i` or `--instance-id` flag
   - Example: `./upload_builders_to_s3.sh --instance-id i-1234567890abcdef0`

2. **"SSM agent is not responding"**
   - **Cause**: The instance doesn't have SSM agent running or properly configured
   - **Solution**: 
     - Ensure SSM agent is installed and running on the instance
     - Verify the instance has the proper IAM role with SSM permissions
     - Check network connectivity to SSM endpoints

3. **"Local path does not exist"**
   - **Cause**: The builder path specified in the script doesn't exist on the target instance
   - **Solution**: Verify the path exists on the target instance (use Windows paths like `D:\\...`)

4. **AWS CLI not found on target instance**
   - **Cause**: AWS CLI is not installed at the expected location
   - **Solution**: Install AWS CLI v2 at `C:\Program Files\Amazon\AWSCLIV2\aws.exe`

5. **Permission denied / S3 access errors**
   - **Cause**: Instance doesn't have S3 write permissions
   - **Solution**: Attach an IAM role with S3 write permissions to the instance

6. **Builder path not found**
   - Verify local paths exist and are accessible on the target instance
   - Check file permissions
   - Use Windows path format with double backslashes (`D:\\path\\to\\builder`)

7. **SSM document creation fails**
   - Ensure you have SSM document creation permissions
   - Check for existing document conflicts

8. **No files uploaded to S3**
   - **Previous behavior**: Script would send command without verifying execution
   - **New behavior**: Script validates instance, monitors execution, and reports results
   - Check the command output for specific errors
   - Verify builder directory contains files

9. **Script stops after validation (FIXED)**
   - **What was happening**: Script would stop silently after "✓ Path configured" message
   - **Root cause**: Arithmetic increment operations causing premature exit with `set -e`
   - **Status**: ✅ Fixed - Script now continues through all steps
   - **If still occurring**: Update to the latest version of the script

10. **PowerShell syntax error in SSM document (FIXED)**
    - **Error message**: `Unexpected token '$LocalPath\"...'`
    - **What was happening**: Over-escaped quotes in PowerShell command logging
    - **Status**: ✅ Fixed - Simplified logging to avoid quote escaping issues
    - **If still occurring**: Run script again to automatically update SSM document to fixed version

11. **SSM document not updating to latest version**
    - **Solution**: The script now automatically creates a new version on each run
    - Verify with: `aws ssm list-document-versions --name "UploadUEBuildersToS3"`
    - If needed, use `--clean` to delete and recreate fresh

### Log Files

Upload operations are logged to:
- Local script: Console output
- SSM execution: `C:\logs\ue-builder-upload-<timestamp>.log` on target instances

## Migration from Old Version

If you were using the previous version of the script that had issues:

### What Changed

**Old Version Issues:**
- ❌ Used `--targets` with tag-based matching (unreliable)
- ❌ No instance validation
- ❌ No progress monitoring
- ❌ Silent failures after validation step
- ❌ PowerShell syntax errors in SSM document
- ❌ No version management

**New Version Features:**
- ✅ Requires explicit `--instance-id` (reliable)
- ✅ Full instance and SSM agent validation
- ✅ Real-time progress monitoring
- ✅ Continues through all steps with proper error handling
- ✅ Fixed PowerShell syntax issues
- ✅ Automatic SSM document versioning

### How to Migrate

```bash
# 1. Update your command to include instance ID
# OLD (doesn't work):
./upload_builders_to_s3.sh

# NEW (working):
./upload_builders_to_s3.sh --instance-id i-046347dd7fd40902e

# 2. Optional: Clean up old SSM document if it exists
./upload_builders_to_s3.sh --clean

# 3. Run with new version (will create/update SSM document automatically)
./upload_builders_to_s3.sh --instance-id i-YOUR-INSTANCE-ID
```

### Breaking Changes

- **Instance ID is now REQUIRED**: Must specify with `-i` or `--instance-id`
- **Script waits for completion**: No longer returns immediately after sending command
- **Exit codes changed**: Now reflects actual upload success/failure

### Compatibility

- Builder path configuration: ✅ Compatible (no changes needed)
- S3 bucket structure: ✅ Compatible (same structure)
- Environment variables: ✅ Compatible (added INSTANCE_ID support)
- Command-line flags: ⚠️ Added `--instance-id` (required), added `--clean`

## Security Considerations

1. **IAM Permissions**: Use least-privilege principle
2. **Bucket Policies**: Consider bucket policies for additional security
3. **Encryption**: Enable S3 server-side encryption for sensitive data
4. **Access Logging**: Enable S3 access logging for audit trails

## Examples

### Example 1: Basic Upload

```bash
# First, find your EC2 instance ID
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' --output table

# Configure builders in script arrays first, then:
./upload_builders_to_s3.sh --instance-id i-1234567890abcdef0
```

### Example 2: Custom Bucket and Region

```bash
./upload_builders_to_s3.sh \
  --instance-id i-1234567890abcdef0 \
  --bucket my-game-builders \
  --region us-west-2
```

### Example 3: Environment Variables

```bash
export INSTANCE_ID="i-1234567890abcdef0"
export BUCKET_NAME="production-builders"
export AWS_REGION="eu-west-1"
./upload_builders_to_s3.sh
```

### Example 4: Configuration Check

```bash
# Show current configuration without executing
./upload_builders_to_s3.sh --show-config

# Dry run to see what would happen (requires instance ID)
./upload_builders_to_s3.sh --instance-id i-1234567890abcdef0 --dry-run
```

### Example 5: SSM Document Management

```bash
# Clean up SSM document
./upload_builders_to_s3.sh --clean

# Or use the alternative flag
./upload_builders_to_s3.sh --delete-document

# Clean with specific region
./upload_builders_to_s3.sh --clean --region us-west-2

# View SSM document versions
aws ssm list-document-versions --name "UploadUEBuildersToS3" --region us-east-1
```

### Example 6: Complete Workflow

```bash
# 1. Check your configuration
./upload_builders_to_s3.sh --show-config

# 2. Find your instance ID
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# 3. Test with dry run
./upload_builders_to_s3.sh \
  --instance-id i-1234567890abcdef0 \
  --dry-run

# 4. Execute the upload (creates/updates SSM document automatically)
./upload_builders_to_s3.sh \
  --instance-id i-1234567890abcdef0 \
  --list

# 5. Verify files in S3
aws s3 ls s3://ue-builders-default/builders/ --recursive --human-readable

# 6. Optional: Clean up SSM document when done
./upload_builders_to_s3.sh --clean
```

## Key Features Summary

### ✅ Reliability
- **Instance Validation**: Verifies instance is running and SSM agent is online before upload
- **Path Validation**: Checks configuration before execution
- **Error Handling**: Comprehensive error checking at every step
- **Real-time Monitoring**: Live progress updates during upload

### 🚀 Automation
- **Automatic Versioning**: SSM document updates automatically on each run
- **Default Version Management**: New versions automatically set as default
- **Bucket Creation**: Creates S3 bucket if it doesn't exist
- **Progress Tracking**: Monitors upload status and displays results

### 🛠️ Maintenance
- **Cleanup Utility**: Easy deletion of SSM documents with `--clean`
- **Version History**: Maintains audit trail of all document versions
- **Detailed Logging**: Comprehensive logs on both local and remote systems
- **Rollback Capability**: Can revert to previous versions if needed

### 📊 Transparency
- **Verbose Output**: Shows exactly what's happening at each step
- **Version Numbers**: Displays SSM document version being used
- **Command IDs**: Provides IDs for manual monitoring if needed
- **Status Indicators**: Clear success/failure indicators throughout

### 🔒 Security
- **IAM Role Support**: Uses instance IAM roles for secure S3 access
- **No Hardcoded Credentials**: Relies on AWS credential chain
- **Instance-Specific**: Targets specific instances, not broad tag matches
- **Validation Before Execution**: Checks permissions before attempting operations

## Support

For issues or questions:
1. Check the log files for detailed error information
2. Verify AWS credentials and permissions
3. Ensure target instances are properly configured
4. Review the troubleshooting section above
5. Check `VERSION_MANAGEMENT.md` for version-related questions
