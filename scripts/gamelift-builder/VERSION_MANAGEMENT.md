# SSM Document Version Management - New Features

## Overview

The `upload_builders_to_s3.sh` script now includes automatic version management for SSM documents and a cleanup utility.

## New Features

### 1. Automatic Version Updates

**Every time you run the script**, it will:
- Check if the SSM document exists
- Create a new version if it exists (or create version 1 if it doesn't)
- Automatically set the new version as the default
- Retain all previous versions for audit/rollback

### 2. Cleanup Command

**New flag**: `--clean` or `--delete-document`

Allows you to delete the SSM document and all its versions when no longer needed.

## Why Automatic Versioning?

### Benefits

1. **Always Up-to-Date**: Ensures you're always using the latest version of the upload script
2. **Audit Trail**: All previous versions are retained for compliance and troubleshooting
3. **Rollback Capability**: Can manually roll back to a previous version if needed
4. **Bug Fixes**: When we fixed the PowerShell syntax error, running the script again automatically deployed the fix

### Version Lifecycle

```
First Run:     Creates document version 1
Second Run:    Creates document version 2, sets as default
Third Run:     Creates document version 3, sets as default
...and so on
```

## Usage Examples

### Normal Upload (Creates/Updates Version Automatically)

```bash
./upload_builders_to_s3.sh --instance-id i-1234567890abcdef0
```

**Output:**
```
Preparing SSM document: UploadUEBuildersToS3
SSM document template found: /path/to/ssm_doc_upload_ue_builders.json
SSM document exists - creating new version...
✓ SSM document updated successfully
  New version: 3
  Setting version 3 as default...
  ✓ Default version updated to 3
SSM document 'UploadUEBuildersToS3' ready.
```

### View Version History

```bash
# List all versions
aws ssm list-document-versions \
  --name "UploadUEBuildersToS3" \
  --region us-east-1

# Output shows:
# Version 1 - Initial creation
# Version 2 - First update
# Version 3 - Current (default)
```

### Clean Up SSM Document

```bash
# Delete the document and ALL versions
./upload_builders_to_s3.sh --clean
```

**Interactive prompt:**
```
SSM Document Cleanup
====================

Deleting SSM document: UploadUEBuildersToS3
Region: us-east-1

Document found. Retrieving details...
  Owner: 123456789012
  Versions: 3

Are you sure you want to delete this SSM document? (y/N):
```

Type `y` to confirm deletion.

### Clean with Specific Region

```bash
./upload_builders_to_s3.sh --clean --region us-west-2
```

## Advanced SSM Document Management

### Get Specific Version Details

```bash
aws ssm describe-document \
  --name "UploadUEBuildersToS3" \
  --document-version "2" \
  --region us-east-1
```

### Manually Set Default Version (Rollback)

```bash
# Roll back to version 2
aws ssm update-document-default-version \
  --name "UploadUEBuildersToS3" \
  --document-version "2" \
  --region us-east-1
```

### View Document History

```bash
# See when each version was created
aws ssm list-document-versions \
  --name "UploadUEBuildersToS3" \
  --region us-east-1 \
  --query 'DocumentVersions[*].[DocumentVersion,CreatedDate,IsDefaultVersion]' \
  --output table
```

## Version Limits

AWS SSM has limits on document versions:
- Maximum 1,000 versions per document
- If you hit the limit, old versions can be manually deleted

### Delete Old Versions (Manual)

```bash
# Delete a specific version
aws ssm delete-document \
  --name "UploadUEBuildersToS3" \
  --document-version "1" \
  --region us-east-1
```

## Best Practices

### Development/Testing
- Run the script freely - new versions are created automatically
- Don't worry about version buildup during testing

### Production
- Each deployment creates a new version (good for audit trail)
- Consider cleaning up old versions periodically (keep last 5-10)
- Document changes in your version control system

### After Major Changes
- The script automatically deploys the new version
- Test thoroughly before production deployment
- Keep previous version numbers noted for rollback if needed

## Troubleshooting

### Issue: "Failed to update SSM document"

**Possible Causes:**
1. No changes detected (document content is identical)
2. JSON syntax error in the SSM document template
3. IAM permission issue

**Solution:**
```bash
# Check if document exists
aws ssm describe-document --name "UploadUEBuildersToS3" --region us-east-1

# View recent versions
aws ssm list-document-versions --name "UploadUEBuildersToS3" --region us-east-1 --max-items 5

# If needed, delete and recreate
./upload_builders_to_s3.sh --clean
./upload_builders_to_s3.sh --instance-id i-XXXXX
```

### Issue: "Could not set default version"

**Impact:** Non-critical - the new version is created but not set as default

**Manual Fix:**
```bash
# Get the latest version number
VERSION=$(aws ssm list-document-versions \
  --name "UploadUEBuildersToS3" \
  --max-items 1 \
  --query 'DocumentVersions[0].DocumentVersion' \
  --output text)

# Set it as default
aws ssm update-document-default-version \
  --name "UploadUEBuildersToS3" \
  --document-version "$VERSION" \
  --region us-east-1
```

### Issue: "Document not found" during cleanup

**Cause:** Document was already deleted or never created

**Resolution:** This is normal - nothing to clean up

## Summary

| Feature | Command | Description |
|---------|---------|-------------|
| **Auto Version** | Normal script run | Creates new version automatically |
| **View Versions** | `aws ssm list-document-versions` | See version history |
| **Clean Up** | `./upload_builders_to_s3.sh --clean` | Delete document and all versions |
| **Rollback** | `aws ssm update-document-default-version` | Manually set older version as default |

## What Changed in the Script?

### Before
- Created document once
- Updated only if explicitly detected
- No version tracking
- No cleanup utility

### After
- ✅ **Automatic versioning** on every run
- ✅ **Sets new version as default** automatically
- ✅ **Extracts and displays version number**
- ✅ **`--clean` flag** for easy cleanup
- ✅ **Interactive deletion** with confirmation prompt
- ✅ **Shows document details** before deletion

## Files Modified

1. `upload_builders_to_s3.sh` - Added version management and cleanup
2. `README.md` - Updated documentation with new features
3. `VERSION_MANAGEMENT.md` - This comprehensive guide

## Get Help

```bash
# View all options including cleanup
./upload_builders_to_s3.sh --help
```

