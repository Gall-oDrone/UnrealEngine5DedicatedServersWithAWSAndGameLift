# Unreal Engine Builder Upload to S3

This directory contains scripts for uploading Unreal Engine builders to an S3 bucket using AWS Systems Manager (SSM).

## Files

- `upload_builders_to_s3.sh` - Main bash script for uploading UE builders to S3
- `ssm/ssm_doc_upload_ue_builders.json` - SSM document for performing the actual upload operations
- `README.md` - This documentation file

## Prerequisites

1. **AWS CLI installed and configured**
   - Install AWS CLI v2
   - Configure with appropriate credentials (`aws configure`)

2. **IAM Permissions**
   - The script needs permissions to:
     - Create/manage S3 buckets
     - Create/update SSM documents
     - Execute SSM commands
   - Target instances need permissions to:
     - Read from local filesystem
     - Write to the specified S3 bucket

3. **Target Instances**
   - Must have AWS CLI installed
   - Must have appropriate IAM role attached
   - Must be accessible via SSM

## Usage

### Configuration

Before running the script, configure your builder paths in the script arrays:

```bash
# Edit the script to configure your builders
nano upload_builders_to_s3.sh

# Update these arrays:
declare -a BUILDER_PATHS=(
    "C:\\UE5\\Builders\\MyGameBuilder"
    "C:\\UE5\\Builders\\AnotherGameBuilder"
    "C:\\UE5\\Builders\\ServerBuilder"
)

declare -a BUILDER_NAMES=(
    "MyGameBuilder"
    "AnotherGameBuilder"
    "ServerBuilder"
)

declare -a BUILDER_S3_KEYS=(
    "builders/MyGameBuilder/"
    "builders/AnotherGameBuilder/"
    "builders/ServerBuilder/"
)
```

### Basic Usage

```bash
# Upload all configured builders
./upload_builders_to_s3.sh

# Show current configuration
./upload_builders_to_s3.sh --show-config
```

### Advanced Usage

```bash
# Specify custom bucket name and region
./upload_builders_to_s3.sh --bucket my-ue-builders --region us-west-2

# Use environment variables
BUCKET_NAME=my-custom-bucket AWS_REGION=eu-west-1 ./upload_builders_to_s3.sh

# Dry run to see what would be done
./upload_builders_to_s3.sh --dry-run

# List bucket contents after upload
./upload_builders_to_s3.sh --list

# Show current configuration
./upload_builders_to_s3.sh --show-config
```

### Command Line Options

- `-h, --help` - Show help message
- `-b, --bucket` - Specify S3 bucket name (default: ue-builders-default)
- `-r, --region` - Specify AWS region (default: us-east-1)
- `-l, --list` - List bucket contents after upload
- `--dry-run` - Show what would be done without executing
- `--show-config` - Show current builder configuration

### Environment Variables

- `BUCKET_NAME` - S3 bucket name (overrides `-b` option)
- `AWS_REGION` - AWS region (overrides `-r` option)

## How It Works

1. **Validation**: The script validates AWS CLI installation, credentials, and builder paths
2. **Bucket Creation**: Creates the S3 bucket if it doesn't exist
3. **SSM Document**: Creates or updates an SSM document for uploading builders
4. **Execution**: Executes the SSM document on target instances to perform the actual upload
5. **Monitoring**: Provides execution ID for monitoring the upload progress

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

After execution, you can monitor the upload progress:

```bash
# Get execution status
aws ssm get-command-invocation --command-id <execution-id> --instance-id <instance-id>

# List all command executions
aws ssm list-command-invocations --command-id <execution-id>
```

## Troubleshooting

### Common Issues

1. **AWS CLI not found**
   - Ensure AWS CLI v2 is installed on target instances
   - Check PATH environment variable

2. **Permission denied**
   - Verify IAM roles and policies
   - Ensure target instances have S3 write permissions

3. **Builder path not found**
   - Verify local paths exist and are accessible
   - Check file permissions

4. **SSM document creation fails**
   - Ensure you have SSM document creation permissions
   - Check for existing document conflicts

### Log Files

Upload operations are logged to:
- Local script: Console output
- SSM execution: `C:\logs\ue-builder-upload-<timestamp>.log` on target instances

## Security Considerations

1. **IAM Permissions**: Use least-privilege principle
2. **Bucket Policies**: Consider bucket policies for additional security
3. **Encryption**: Enable S3 server-side encryption for sensitive data
4. **Access Logging**: Enable S3 access logging for audit trails

## Examples

### Example 1: Basic Upload

```bash
# Configure builders in script arrays first, then:
./upload_builders_to_s3.sh
```

### Example 2: Custom Bucket and Region

```bash
./upload_builders_to_s3.sh \
  --bucket my-game-builders \
  --region us-west-2
```

### Example 3: Environment Variables

```bash
export BUCKET_NAME="production-builders"
export AWS_REGION="eu-west-1"
./upload_builders_to_s3.sh
```

### Example 4: Configuration Check

```bash
# Show current configuration without executing
./upload_builders_to_s3.sh --show-config

# Dry run to see what would happen
./upload_builders_to_s3.sh --dry-run
```

## Support

For issues or questions:
1. Check the log files for detailed error information
2. Verify AWS credentials and permissions
3. Ensure target instances are properly configured
4. Review the troubleshooting section above
