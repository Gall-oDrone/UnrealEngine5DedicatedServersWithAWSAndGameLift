# Changes Summary - FPSTemplate GameLift Deployment

## Overview
Modified the GameLift Anywhere development instance deployment scripts to work with the FPSTemplate Unreal Engine 5 game server on Amazon Linux 2023.

## Files Modified

### 1. `deploy_dev_instance.sh`
**Key Changes:**
- ✅ Added automatic directory detection to work from any location
- ✅ Added `SOURCE_BUCKET_NAME` variable for downloading game server builds from S3
- ✅ Downloads `FPSTemplateServer.zip` from S3 path: `builders/Linux/Server/FPSTemplate/FPSTemplateServer.zip`
- ✅ Fixed Maven check (was checking `java` instead of `mvn`)
- ✅ Removed dependency on local `AmazonGameLiftSampleServerBinary.zip` file
- ✅ Updated fleet LaunchPath to: `/local/game/LinuxServer/FPSTemplateServer`
- ✅ Added automatic deployment testing (creates a test game session)
- ✅ Added comprehensive status output with helpful commands
- ✅ Added automatic JSON template restoration after deployment

**New Sections:**
- Section 1: Download game server build from S3
- Section 7: Test the deployment with automatic game session creation

### 2. `dev-game-server-setup-and-deployment.json`
**Key Changes:**
- ✅ Updated Java installation to use Amazon Corretto 23 for Amazon Linux 2023
  - Old: `sudo yum install java -y`
  - New: `sudo yum install java-23-amazon-corretto-headless -y`
- ✅ Changed game server zip file from `AmazonGameLiftSampleServerBinary.zip` to `FPSTemplateServer.zip`
- ✅ Added executable permissions after unzip:
  - `chmod +x LinuxServer/FPSTemplateServer`
  - `chmod +x LinuxServer/FPSTemplateServer.sh` (if exists)

### 3. `update_game_server.sh` (NEW FILE)
**Purpose:** Deploy updated game server versions without recreating infrastructure

**Features:**
- Downloads latest `FPSTemplateServer.zip` from S3
- Uploads to deployment bucket
- Triggers SSM deployment
- GameLift Agent automatically restarts with new server
- Provides monitoring commands and status information

### 4. `README.md`
**Updated Sections:**
- Prerequisites: Now mentions Amazon Corretto 23 and S3 upload requirement
- Files Description: Added details about all three scripts
- Usage: Complete rewrite with initial deployment and update deployment instructions
- Configuration Parameters: Clarified automatic vs manual configuration
- Troubleshooting: Comprehensive section with:
  - SERVER_PROCESS_INVALID_PATH solution
  - Java installation for Amazon Linux 2023
  - Permission issues
  - File path errors
  - Server status checking commands
  - Fleet information commands

### 5. `CHANGES_SUMMARY.md` (THIS FILE - NEW)
Complete documentation of all changes made

## Configuration Required

Before running the scripts, update these variables in both `deploy_dev_instance.sh` and `update_game_server.sh`:

```bash
# In deploy_dev_instance.sh and update_game_server.sh
BUCKET_NAME="your-unique-bucket-name"           # For deployment resources
SOURCE_BUCKET_NAME="your-source-bucket-name"     # Where FPSTemplateServer.zip is stored
```

## Prerequisites

1. **Game Server Build**: 
   - Build FPSTemplate for Linux Server
   - Upload to S3: `s3://your-bucket/builders/Linux/Server/FPSTemplate/FPSTemplateServer.zip`

2. **Local Tools**:
   - AWS CLI configured with credentials
   - Java (Amazon Corretto 23 recommended)
   - Maven (for building GameLift Agent)

3. **AWS Permissions**:
   - EC2, IAM, GameLift, S3, SSM, CloudWatch

## Usage

### Initial Deployment
```bash
# Edit configuration
vim deploy_dev_instance.sh  # Update BUCKET_NAME and SOURCE_BUCKET_NAME

# Run deployment
./deploy_dev_instance.sh
```

The script will:
1. Download game server from S3
2. Validate prerequisites
3. Create AWS infrastructure
4. Deploy to EC2 instance
5. Test with a game session
6. Display status and helpful commands

### Update Deployment
```bash
# After making changes to your game server
./update_game_server.sh
```

## Key Improvements

### Fixed Issues
1. ✅ **SERVER_PROCESS_INVALID_PATH**: Corrected LaunchPath to match actual executable location
2. ✅ **Java Installation**: Using correct package for Amazon Linux 2023
3. ✅ **File Path Errors**: Auto-detect script directory
4. ✅ **Permission Issues**: Automatically set executable permissions
5. ✅ **Maven Check**: Fixed to actually check for Maven instead of Java

### New Features
1. ✅ **Automatic Testing**: Creates test game session after deployment
2. ✅ **Update Script**: Easy updates without infrastructure recreation
3. ✅ **Better Output**: Comprehensive status information and helpful commands
4. ✅ **JSON Restoration**: Automatically restores template after deployment
5. ✅ **Error Handling**: Better error messages and validation

## Server Configuration

- **Executable Path**: `/local/game/LinuxServer/FPSTemplateServer`
- **Server Port**: 1935 (TCP)
- **Log File**: `/local/game/logs/myserver1935.log`
- **Fleet Type**: GameLift Anywhere
- **Location**: `custom-mygame-dev-location`
- **Instance Type**: Amazon Linux 2023, m6i.large

## Testing the Deployment

### Check Fleet Status
```bash
FLEET_ID=$(aws gamelift describe-fleet-attributes --query 'FleetAttributes[?Name==`MyGame-Test-Fleet`].FleetId' --output text)
aws gamelift describe-instances --fleet-id $FLEET_ID
```

### Create Game Session
```bash
aws gamelift create-game-session \
  --fleet-id $FLEET_ID \
  --region us-east-1 \
  --maximum-player-session-count 5 \
  --location custom-mygame-dev-location
```

### Check Server Logs
```bash
# SSH into instance
aws ssm start-session --target <INSTANCE_ID>

# View logs
tail -f /local/game/logs/myserver1935.log
```

### Check Processes
```bash
# In SSM session
ps aux | grep GameLiftAgent
ps aux | grep FPSTemplate
```

## Troubleshooting

See the comprehensive troubleshooting section in `README.md` for:
- SERVER_PROCESS_INVALID_PATH solutions
- Java installation issues
- Permission problems
- File path errors
- Status checking commands

## References

- [Amazon GameLift Toolkit](https://github.com/amazon-gamelift/amazon-gamelift-toolkit)
- [GameLift Anywhere Documentation](https://docs.aws.amazon.com/gamelift/latest/developerguide/gamelift-anywhere.html)
- [Amazon Linux 2023 Java Installation](https://docs.aws.amazon.com/corretto/latest/corretto-23-ug/amazon-linux-install.html)

## Changes Date
October 10, 2025

