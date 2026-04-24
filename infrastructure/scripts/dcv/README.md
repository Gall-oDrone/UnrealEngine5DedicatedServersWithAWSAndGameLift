# NICE DCV Installation Scripts

This directory contains scripts and documentation for deploying DCV (Desktop and Cloud Visualization) on Windows EC2 instances via AWS Systems Manager (SSM).

## Files

- **`dcv_install.ps1`** - PowerShell script that installs DCV on Windows instances
- **`setup_dcv.sh`** - Bash script for deploying DCV via SSM from Linux/macOS
- **`README.md`** - This documentation file

## Quick Start

### Prerequisites

- AWS CLI installed and configured
- SSM agent running on target Windows instance
- Appropriate IAM permissions for SSM operations
- Instance must be in "running" state

### Option 1: Deploy via SSM (Upload First Method) - Recommended

This method uploads the PowerShell script to the instance first, then executes it.

```bash
# Deploy DCV using the upload method
./setup_dcv.sh deploy-upload i-0a0cf65b6a9a9b7d0
```

**What this does:**
1. Downloads the PowerShell script from a remote URL to the instance
2. Executes the script with proper execution policy
3. Monitors the installation progress
4. Provides connection information

### Option 2: Deploy via SSM (Base64 Method)

This method encodes the local PowerShell script and sends it in one command.

```bash
# Deploy DCV using the base64 method
./setup_dcv.sh deploy-base64 i-0a0cf65b6a9a9b7d0
```

**What this does:**
1. Base64 encodes the local `dcv_install.ps1` script
2. Sends and executes the script in one SSM command
3. Monitors the installation progress
4. Provides connection information

### Option 3: Manual SSM Commands

You can also run the SSM commands manually:

#### Upload First, Then Execute (Recommended)
```bash
# First, upload the script to the Windows instance
aws ssm send-command \
  --instance-ids i-0a0cf65b6a9a9b7d0 \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Invoke-WebRequest -Uri https://raw.githubusercontent.com/YOUR_REPO/dcv_install.ps1 -OutFile C:\\dcv_install.ps1"]' \
  --output text

# Then execute it
aws ssm send-command \
  --instance-ids i-0a0cf65b6a9a9b7d0 \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force; C:\\dcv_install.ps1"]' \
  --output text
```

#### Base64 Encode and Send
```bash
# Base64 encode the script
base64 -w 0 dcv_install.ps1 > script.b64

# Send and execute in one command
aws ssm send-command \
  --instance-ids i-0a0cf65b6a9a9b7d0 \
  --document-name "AWS-RunPowerShellScript" \
  --parameters "commands=[\"[System.IO.File]::WriteAllText('C:\\dcv_install.ps1', [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$(cat script.b64)'))); Set-ExecutionPolicy RemoteSigned -Force; C:\\dcv_install.ps1\"]" \
  --output text
```

## Monitoring and Management

### Monitor Installation Progress

```bash
# Monitor the last deployment
./setup_dcv.sh monitor i-0a0cf65b6a9a9b7d0

# Monitor specific command ID
./setup_dcv.sh monitor i-0a0cf65b6a9a9b7d0 COMMAND_ID
```

### Check Installation Logs

```bash
# Check recent installation logs
./setup_dcv.sh logs i-0a0cf65b6a9a9b7d0
```

### Get Connection Information

```bash
# Get instance connection details
./setup_dcv.sh info i-0a0cf65b6a9a9b7d0
```

### Manual SSM Monitoring

```bash
# Check command status (replace COMMAND_ID with actual ID)
aws ssm get-command-invocation \
  --command-id COMMAND_ID \
  --instance-id i-0a0cf65b6a9a9b7d0

# Check the log file after execution
aws ssm send-command \
  --instance-ids i-0a0cf65b6a9a9b7d0 \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Get-Content C:\\logs\\dcv-install.log -Tail 50"]' \
  --output text
```

## What the PowerShell Script Does

The `dcv_install.ps1` script performs the following operations:

### 1. **Installs Prerequisites**
- Installs Chocolatey package manager
- Installs Visual C++ Redistributables (required for DCV 2024.0)

### 2. **Downloads DCV Components**
- DCV Server MSI installer (v2024.0-17979)
- DCV Virtual Display Driver MSI (for Windows Server 2016)

### 3. **Installs DCV**
- DCV Server with automatic session configuration
- Virtual Display Driver (if needed for older Windows versions)
- Sets session owner to Administrator

### 4. **Configures Services**
- Starts DCV Server service
- Creates console session automatically
- Sets services to start automatically

### 5. **Logging and Monitoring**
- Creates comprehensive installation logs
- Provides status information
- Displays connection details

## Configuration

The scripts use these default settings:

### PowerShell Script (`dcv_install.ps1`)
```powershell
$DCVServerURL = "https://d1uj6qtbmh3dt5.cloudfront.net/2024.0/Servers/nice-dcv-server-x64-Release-2024.0-17979.msi"
$DCVDisplayURL = "https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-virtual-display-x64-Release.msi"
$SessionOwner = "Administrator"
```

### Bash Script (`setup_dcv.sh`)
```bash
DCV_SERVER_VERSION="2024.0-17979"
DCV_SESSION_NAME="ue5-session"
DCV_PORT="8443"
DCV_SESSION_OWNER="Administrator"
POWERSHELL_SCRIPT_URL="https://raw.githubusercontent.com/YOUR_REPO/dcv_install.ps1"
```

## Output Files

After successful installation, you'll find:

### On the Windows Instance
- **`C:\logs\dcv-install.log`** - Full installation transcript
- **`C:\logs\dcv-server-msi.log`** - DCV Server MSI installation log
- **`C:\logs\dcv-display-msi.log`** - Display Driver MSI installation log (if installed)

### On the Local Machine (where you ran setup_dcv.sh)
- **`dcv_setup.log`** - SSM deployment log
- **`last_command_id.txt`** - Last SSM command ID for monitoring

## Verification

### Check if DCV is Running

You can verify the installation using the monitoring commands:

```bash
# Check installation logs
./setup_dcv.sh logs i-0a0cf65b6a9a9b7d0

# Get connection information
./setup_dcv.sh info i-0a0cf65b6a9a9b7d0
```

Or manually via SSM:

```bash
# Check service status
aws ssm send-command \
  --instance-ids i-0a0cf65b6a9a9b7d0 \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Get-Service -Name \"DCV Server\""]'

# Check if port is listening
aws ssm send-command \
  --instance-ids i-0a0cf65b6a9a9b7d0 \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["netstat -an | findstr :8443"]'

# List DCV sessions
aws ssm send-command \
  --instance-ids i-0a0cf65b6a9a9b7d0 \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["& \"C:\\Program Files\\NICE\\DCV\\Server\\bin\\dcv.exe\" list-sessions"]'
```

### Test Connectivity

1. **Ensure port 8443 is open** in your security group
2. **Get the public IP** using: `./setup_dcv.sh info i-0a0cf65b6a9a9b7d0`
3. **Open browser** to `https://<YOUR_PUBLIC_IP>:8443`
4. **Accept the certificate warning**
5. **Login with Windows Administrator credentials**

## Troubleshooting

### Common Issues

#### 1. **SSM Command Failures**
```bash
# Check if SSM agent is running
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-0a0cf65b6a9a9b7d0"

# Check command status
aws ssm get-command-invocation --command-id COMMAND_ID --instance-id i-0a0cf65b6a9a9b7d0
```

#### 2. **PowerShell Execution Policy Error**
The script automatically sets the execution policy, but if it fails:
```bash
aws ssm send-command \
  --instance-ids i-0a0cf65b6a9a9b7d0 \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force"]'
```

#### 3. **Download Failures**
- Check internet connectivity on the instance
- Verify URLs are accessible
- Check Windows Firewall outbound rules
- Check security group outbound rules

#### 4. **Installation Failures**
- Check logs using: `./setup_dcv.sh logs i-0a0cf65b6a9a9b7d0`
- Verify instance has sufficient disk space
- Check Windows Event Logs via SSM

#### 5. **Service Won't Start**
- Check Windows Event Logs via SSM
- Verify dependencies are installed
- Check if instance has required Windows version

### Log Files

#### On Windows Instance
- **`C:\logs\dcv-install.log`** - Full installation transcript
- **`C:\logs\dcv-server-msi.log`** - DCV Server MSI installation log
- **`C:\logs\dcv-display-msi.log`** - Display Driver MSI installation log

#### On Local Machine
- **`dcv_setup.log`** - SSM deployment log
- **`last_command_id.txt`** - Last SSM command ID for monitoring

## Security Considerations

### For Development
- Self-signed certificates are acceptable
- Authentication uses Windows accounts
- Port 8443 is open to all sources (0.0.0.0/0)
- SSM commands run with elevated privileges

### For Production
- Use proper SSL certificates
- Restrict port 8443 to specific IP ranges
- Enable additional authentication methods
- Review and harden configuration
- Implement proper IAM roles for SSM

## IAM Permissions Required

The user/role running the deployment script needs these permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:SendCommand",
                "ssm:GetCommandInvocation",
                "ssm:DescribeInstanceInformation",
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        }
    ]
}
```

## Next Steps

After successful DCV installation:

1. **Test connectivity** using: `./setup_dcv.sh info i-0a0cf65b6a9a9b7d0`
2. **Access DCV web interface** in your browser
3. **Create additional sessions** if needed
4. **Configure user access** and permissions
5. **Set up monitoring** and logging

## Support

If you encounter issues:

1. Check the log files using: `./setup_dcv.sh logs i-0a0cf65b6a9a9b7d0`
2. Monitor installation progress: `./setup_dcv.sh monitor i-0a0cf65b6a9a9b7d0`
3. Verify SSM agent is running on the instance
4. Check security group configuration
5. Review Windows Event Logs via SSM
6. Test network connectivity to port 8443

## File Locations

- **PowerShell Script**: `scripts/dcv/dcv_install.ps1`
- **Bash Deployment Script**: `scripts/dcv/setup_dcv.sh`
- **Documentation**: `scripts/dcv/README.md`
