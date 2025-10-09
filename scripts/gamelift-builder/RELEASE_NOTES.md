# Release Notes - Unreal Engine Builder Upload Script

## Version 2.0 (Current) - Production Ready

### 🎉 Major Release - Complete Rewrite

This release fixes critical bugs and adds production-ready features for reliable Unreal Engine builder uploads to S3 via AWS Systems Manager.

---

## What's Fixed ✅

### 1. Silent Failure Bug (Critical)
- **Issue**: Script would stop silently after validation step
- **Cause**: Arithmetic increment operations with `set -e` causing premature exit
- **Fix**: Added `|| true` to all increment operations
- **Impact**: Script now completes all steps successfully

### 2. PowerShell Syntax Error (Critical)
- **Issue**: `Unexpected token '$LocalPath\"...'` error during upload
- **Cause**: Over-escaped quotes in PowerShell command logging
- **Fix**: Simplified logging to avoid complex quote escaping
- **Impact**: Uploads now execute without PowerShell errors

### 3. Unreliable Instance Targeting (Major)
- **Issue**: Used `--targets` with tag matching that often found no instances
- **Cause**: Generic tag-based targeting without validation
- **Fix**: Now requires explicit `--instance-id` with validation
- **Impact**: Commands reliably reach the target instance

### 4. No Progress Feedback (Major)
- **Issue**: Script sent command and exited, no way to know if upload succeeded
- **Cause**: No monitoring of command execution
- **Fix**: Added real-time progress monitoring with status updates
- **Impact**: Users see upload progress and success/failure status

### 5. Missing Error Handling (Major)
- **Issue**: Errors weren't properly caught or reported
- **Cause**: Insufficient validation and error checking
- **Fix**: Added validation at every step with detailed error messages
- **Impact**: Clear error messages help troubleshoot issues

---

## What's New 🚀

### 1. Automatic Version Management
- **Feature**: SSM document automatically creates new versions on each run
- **Benefit**: Always uses latest version, maintains audit trail
- **Usage**: Automatic - no user action needed
- **Example**: Version 1 → Version 2 → Version 3 (auto-incremented)

### 2. Cleanup Utility
- **Feature**: New `--clean` flag to delete SSM document
- **Benefit**: Easy cleanup when document no longer needed
- **Usage**: `./upload_builders_to_s3.sh --clean`
- **Safety**: Interactive confirmation before deletion

### 3. Instance Validation
- **Feature**: Pre-flight checks before upload
- **Checks**:
  - Instance exists and is running
  - SSM agent is online
  - Instance is accessible
- **Benefit**: Catches configuration issues before attempting upload

### 4. Real-time Monitoring
- **Feature**: Live progress updates during upload
- **Shows**:
  - Upload initiation
  - Progress indicators
  - Success/failure status
  - Command output and errors
- **Timeout**: 10 minutes with manual check instructions

### 5. Enhanced Logging
- **Features**:
  - Version numbers displayed
  - Step-by-step progress
  - Clear success/failure indicators
  - Command IDs for manual monitoring
- **Locations**:
  - Local: Console output
  - Remote: `C:\logs\ue-builder-upload-<timestamp>.log`

---

## Breaking Changes ⚠️

### 1. Instance ID Now Required
**Old:**
```bash
./upload_builders_to_s3.sh
```

**New:**
```bash
./upload_builders_to_s3.sh --instance-id i-1234567890abcdef0
```

**Reason**: Ensures reliable instance targeting

### 2. Script Waits for Completion
**Old Behavior**: Returns immediately after sending command

**New Behavior**: Waits for upload to complete (up to 10 minutes)

**Reason**: Provides feedback on actual success/failure

### 3. Exit Codes Changed
**Old**: Always exits 0 (even on failure)

**New**: 
- Exit 0: Success
- Exit 1: Failure

**Reason**: Enables automation and error detection

---

## Migration Guide

### For Existing Users

```bash
# Step 1: Find your instance ID
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Step 2: Optional - Clean up old SSM document
./upload_builders_to_s3.sh --clean

# Step 3: Run with new syntax
./upload_builders_to_s3.sh --instance-id i-YOUR-INSTANCE-ID
```

### What Stays the Same

✅ Builder path configuration (BUILDER_PATHS, BUILDER_NAMES, BUILDER_S3_KEYS)
✅ S3 bucket structure
✅ Environment variables (BUCKET_NAME, AWS_REGION)
✅ SSM document functionality (enhanced, but compatible)

---

## Upgrade Instructions

### From Version 1.x

1. **Pull latest changes**
   ```bash
   cd /path/to/scripts/gamelift-builder
   git pull origin main
   ```

2. **Review configuration**
   ```bash
   ./upload_builders_to_s3.sh --show-config
   ```

3. **Get instance ID**
   ```bash
   aws ec2 describe-instances \
     --filters "Name=instance-state-name,Values=running" \
     --output table
   ```

4. **Test with dry run**
   ```bash
   ./upload_builders_to_s3.sh --instance-id i-XXXXX --dry-run
   ```

5. **Execute upload**
   ```bash
   ./upload_builders_to_s3.sh --instance-id i-XXXXX
   ```

---

## Version Comparison

| Feature | v1.x | v2.0 |
|---------|------|------|
| Instance Targeting | Tag-based | Explicit ID |
| Instance Validation | ❌ None | ✅ Full validation |
| Progress Monitoring | ❌ None | ✅ Real-time |
| Error Handling | ⚠️ Basic | ✅ Comprehensive |
| SSM Versioning | ❌ None | ✅ Automatic |
| Cleanup Utility | ❌ None | ✅ `--clean` flag |
| PowerShell Errors | ❌ Yes | ✅ Fixed |
| Silent Failures | ❌ Yes | ✅ Fixed |
| Exit Codes | ⚠️ Always 0 | ✅ Proper codes |
| Documentation | ⚠️ Basic | ✅ Comprehensive |

---

## Known Issues

None! All previously reported issues have been fixed.

If you encounter any issues, please:
1. Check the troubleshooting section in README.md
2. Review the detailed error messages in the output
3. Check instance SSM agent status
4. Verify IAM permissions

---

## Future Enhancements (Planned)

- [ ] Support for multiple regions
- [ ] Parallel uploads for multiple builders
- [ ] Compression before upload (optional)
- [ ] Delta uploads (only changed files)
- [ ] Upload resume capability
- [ ] Email notifications on completion
- [ ] CloudWatch metrics integration

---

## Documentation

- **README.md** - Complete usage guide
- **VERSION_MANAGEMENT.md** - Version management details
- **RELEASE_NOTES.md** - This file

---

## Acknowledgments

**Issues Fixed**:
- Silent failure after validation
- PowerShell syntax errors
- Unreliable instance targeting
- Missing progress feedback
- Inadequate error handling

**Features Added**:
- Automatic version management
- Cleanup utility
- Instance validation
- Real-time monitoring
- Enhanced logging

---

## Quick Reference

```bash
# Basic upload
./upload_builders_to_s3.sh --instance-id i-XXXXX

# With custom bucket
./upload_builders_to_s3.sh -i i-XXXXX --bucket my-bucket

# Show configuration
./upload_builders_to_s3.sh --show-config

# Dry run
./upload_builders_to_s3.sh -i i-XXXXX --dry-run

# Clean up SSM document
./upload_builders_to_s3.sh --clean

# List uploaded files
./upload_builders_to_s3.sh -i i-XXXXX --list
```

---

**Version**: 2.0  
**Release Date**: October 2025  
**Status**: ✅ Production Ready  
**Stability**: Stable

