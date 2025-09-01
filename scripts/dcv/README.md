# NICE DCV Installation Scripts

This directory contains documentation and scripts for DCV installation. The actual installation scripts are located in the `modules/compute/templates/` folder.

## Files

- **`modules/compute/templates/install-dcv-only.ps1`** - PowerShell script that installs only DCV
- **`modules/compute/templates/install-dcv-only.bat`** - Windows batch file launcher for the PowerShell script
- **`setup_dcv.sh`** - Linux/macOS script for DCV setup (if needed)

## Quick Start

### Option 1: Run PowerShell Script Directly

1. **Download the script** to your Windows instance from `modules/compute/templates/install-dcv-only.ps1`
2. **Open PowerShell as Administrator**
3. **Run the script:**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force
   .\install-dcv-only.ps1
   ```

### Option 2: Use Batch File Launcher

1. **Download both files** to your Windows instance from `modules/compute/templates/`
2. **Double-click** `install-dcv-only.bat`
3. **Or run from Command Prompt:**
   ```cmd
   install-dcv-only.bat
   ```

### Option 3: Run via SSM (if instance is online)

```bash
aws ssm send-command \
  --instance-ids <INSTANCE_ID> \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force; .\install-dcv-only.ps1"]'
```

## What the Script Does

### 1. **Downloads DCV Components**
- DCV Server MSI installer
- DCV Virtual Display Driver MSI

### 2. **Installs DCV**
- DCV Server (main application)
- Virtual Display Driver (for headless operation)

### 3. **Configures DCV**
- Creates configuration file (`C:\ProgramData\NICE\dcv\conf\dcv.conf`)
- Sets port to 8443
- Configures authentication and session management

### 4. **Configures Windows Firewall**
- Adds inbound rules for TCP port 8443
- Adds inbound rules for UDP port 8443

### 5. **Creates SSL Certificate**
- Self-signed certificate for HTTPS access
- Valid for 2 years

### 6. **Starts Services**
- Starts DCV Server service
- Creates console session
- Sets up scheduled task for reboot

## Configuration

The script uses these default settings:

```powershell
$DCVVersion = "2023.2-15773"
$DCVSessionName = "ue5-session"
$DCVPort = "8443"
```

## Output Files

After successful installation, you'll find:

- **`C:\logs\dcv-install.log`** - Full installation transcript
- **`C:\logs\dcv-install-complete.txt`** - Installation status summary
- **`C:\inetpub\wwwroot\dcv-status.html`** - Web status page (if IIS available)

## Verification

### Check if DCV is Running

```powershell
# Check service status
Get-Service -Name "DCV Server"

# Check if port is listening
netstat -an | findstr :8443

# List DCV sessions
& "C:\Program Files\NICE\DCV\Server\bin\dcv.exe" list-sessions
```

### Test Connectivity

1. **Ensure port 8443 is open** in your security group
2. **Open browser** to `https://<YOUR_PUBLIC_IP>:8443`
3. **Accept the certificate warning**
4. **Login with Windows Administrator credentials**

## Troubleshooting

### Common Issues

#### 1. **Execution Policy Error**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force
```

#### 2. **Download Failures**
- Check internet connectivity
- Verify URLs are accessible
- Check Windows Firewall outbound rules

#### 3. **Installation Failures**
- Check logs in `C:\logs\`
- Ensure running as Administrator
- Check available disk space

#### 4. **Service Won't Start**
- Check Windows Event Logs
- Verify dependencies are installed
- Check configuration file syntax

### Log Files

- **`dcv-install.log`** - Full installation transcript
- **`dcv-server-install.log`** - DCV Server MSI installation log
- **`dcv-display-install.log`** - Display Driver MSI installation log

## Security Considerations

### For Development
- Self-signed certificates are acceptable
- Authentication is set to "system" (Windows accounts)
- Port 8443 is open to all sources (0.0.0.0/0)

### For Production
- Use proper SSL certificates
- Restrict port 8443 to specific IP ranges
- Enable additional authentication methods
- Review and harden configuration

## Next Steps

After successful DCV installation:

1. **Test connectivity** to port 8443
2. **Access DCV web interface** in your browser
3. **Create additional sessions** if needed
4. **Configure user access** and permissions
5. **Set up monitoring** and logging

## Support

If you encounter issues:

1. Check the log files in `C:\logs\`
2. Verify Windows Firewall rules
3. Check security group configuration
4. Review Windows Event Logs
5. Test network connectivity to port 8443

## File Locations

- **Installation Scripts**: `modules/compute/templates/`
- **Documentation**: `scripts/dcv/`
- **Main User Data**: `modules/compute/templates/user_data.ps1`
