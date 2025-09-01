<powershell>
# NICE DCV Installation Script (DCV Only)
# This script installs and configures NICE DCV for high-performance remote access

# Set execution policy to allow script execution
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# DCV Configuration
$DCVVersion = "2023.2-15773"
$DCVSessionName = "ue5-session"
$DCVPort = "8443"

# Create log directory
$LogDir = "C:\logs"
New-Item -ItemType Directory -Force -Path $LogDir
Start-Transcript -Path "$LogDir\dcv-install.log" -Append

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Starting NICE DCV Installation..." -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "DCV Version: $DCVVersion" -ForegroundColor Yellow
Write-Host "Port: $DCVPort" -ForegroundColor Yellow
Write-Host "Session Name: $DCVSessionName" -ForegroundColor Yellow
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Yellow

# ═══════════════════════════════════════════════════════════════════════════════
# NICE DCV Installation Section
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "Installing NICE DCV for high-performance remote access..." -ForegroundColor Green

# Create DCV download directory
$DCVDownloadDir = "C:\dcv-install"
New-Item -ItemType Directory -Force -Path $DCVDownloadDir

# Download DCV components
Write-Host "Downloading DCV Server..." -ForegroundColor Yellow
$DCVServerURL = "https://d1uj6qtbmh3dt5.cloudfront.net/2023.2/Servers/nice-dcv-server-$DCVVersion.x86_64.msi"
$DCVServerMSI = "$DCVDownloadDir\dcv-server.msi"

try {
    Invoke-WebRequest -Uri $DCVServerURL -OutFile $DCVServerMSI -UseBasicParsing
    Write-Host "✅ DCV Server downloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to download DCV Server: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Downloading DCV Virtual Display Driver..." -ForegroundColor Yellow
$DCVDisplayURL = "https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-virtual-display-x64-Release.msi"
$DCVDisplayMSI = "$DCVDownloadDir\dcv-display.msi"

try {
    Invoke-WebRequest -Uri $DCVDisplayURL -OutFile $DCVDisplayMSI -UseBasicParsing
    Write-Host "✅ DCV Virtual Display Driver downloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to download DCV Virtual Display Driver: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Install DCV Server
Write-Host "Installing DCV Server..." -ForegroundColor Yellow
try {
    $process = Start-Process msiexec.exe -ArgumentList "/i `"$DCVServerMSI`" /quiet /norestart /l*v `"$LogDir\dcv-server-install.log`"" -Wait -PassThru
    if ($process.ExitCode -eq 0) {
        Write-Host "✅ DCV Server installed successfully" -ForegroundColor Green
    } else {
        Write-Host "❌ DCV Server installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Failed to install DCV Server: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Install DCV Virtual Display Driver (for headless operation)
Write-Host "Installing DCV Virtual Display Driver..." -ForegroundColor Yellow
try {
    $process = Start-Process msiexec.exe -ArgumentList "/i `"$DCVDisplayMSI`" /quiet /norestart /l*v `"$LogDir\dcv-display-install.log`"" -Wait -PassThru
    if ($process.ExitCode -eq 0) {
        Write-Host "✅ DCV Virtual Display Driver installed successfully" -ForegroundColor Green
    } else {
        Write-Host "❌ DCV Virtual Display Driver installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Failed to install DCV Virtual Display Driver: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Configure DCV
Write-Host "Configuring DCV..." -ForegroundColor Yellow

# Create DCV configuration directory
$DCVConfigDir = "C:\ProgramData\NICE\dcv\conf"
New-Item -ItemType Directory -Force -Path $DCVConfigDir

# Create DCV configuration file
$DCVConfig = @"
[connectivity]
web-port=$DCVPort

[security]
auth-token-verifier=""
authentication="system"

[session-management]
create-session=true

[session-management/automatic-console-session]
owner="Administrator"

[display]
target-fps=30

[windows]
disable-display-sleep=true
"@

try {
    $DCVConfig | Out-File -FilePath "$DCVConfigDir\dcv.conf" -Encoding ASCII
    Write-Host "✅ DCV configuration file created successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to create DCV configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Configure Windows Firewall for DCV
Write-Host "Configuring Windows Firewall for DCV..." -ForegroundColor Yellow
try {
    New-NetFirewallRule -DisplayName "DCV Server" -Direction Inbound -Protocol TCP -LocalPort $DCVPort -Action Allow -ErrorAction Stop
    New-NetFirewallRule -DisplayName "DCV Server UDP" -Direction Inbound -Protocol UDP -LocalPort $DCVPort -Action Allow -ErrorAction Stop
    Write-Host "✅ Windows Firewall rules configured successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to configure Windows Firewall: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create self-signed certificate for DCV (development only)
Write-Host "Creating self-signed certificate for DCV..." -ForegroundColor Yellow
try {
    $cert = New-SelfSignedCertificate -DnsName "localhost", "*.amazonaws.com" -CertStoreLocation "Cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(2) -ErrorAction Stop
    $certPath = "Cert:\LocalMachine\My\" + $cert.Thumbprint
    Export-Certificate -Cert $certPath -FilePath "C:\ProgramData\NICE\dcv\cert.cer" -ErrorAction Stop
    Write-Host "✅ Self-signed certificate created successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to create certificate: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Set DCV to use the console session
Write-Host "Configuring DCV for console session..." -ForegroundColor Yellow
try {
    & "C:\Program Files\NICE\DCV\Server\bin\dcv.exe" set-permissions --session console --user Administrator --all-permissions
    Write-Host "✅ DCV console session permissions configured" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Warning: Could not configure console session permissions: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Start DCV Server service
Write-Host "Starting DCV Server service..." -ForegroundColor Yellow
try {
    Set-Service -Name "DCV Server" -StartupType Automatic -ErrorAction Stop
    Start-Service -Name "DCV Server" -ErrorAction Stop
    Write-Host "✅ DCV Server service started successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to start DCV Server service: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Wait for service to fully start
Write-Host "Waiting for DCV Server service to fully initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Verify service is running
$dcvService = Get-Service -Name "DCV Server" -ErrorAction SilentlyContinue
if ($dcvService -and $dcvService.Status -eq "Running") {
    Write-Host "✅ DCV Server service is running" -ForegroundColor Green
} else {
    Write-Host "❌ DCV Server service is not running" -ForegroundColor Red
    exit 1
}

# Create DCV session
Write-Host "Creating DCV session..." -ForegroundColor Yellow
try {
    $sessionResult = & "C:\Program Files\NICE\DCV\Server\bin\dcv.exe" create-session --type=console --owner Administrator $DCVSessionName 2>&1
    Write-Host "✅ DCV session '$DCVSessionName' created successfully" -ForegroundColor Green
    Write-Host "Session details: $sessionResult" -ForegroundColor Cyan
} catch {
    Write-Host "⚠️ Warning: DCV session creation might require manual setup after reboot: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Create a scheduled task to recreate DCV session on reboot
Write-Host "Creating scheduled task for DCV session..." -ForegroundColor Yellow
try {
    $action = New-ScheduledTaskAction -Execute "C:\Program Files\NICE\DCV\Server\bin\dcv.exe" -Argument "create-session --type=console --owner Administrator $DCVSessionName"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "CreateDCVSession" -Action $action -Trigger $trigger -Principal $principal -Description "Create DCV session on startup" -ErrorAction Stop
    Write-Host "✅ Scheduled task created successfully" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Warning: Could not create scheduled task: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════════
# End of NICE DCV Installation
# ═══════════════════════════════════════════════════════════════════════════════

# Create completion marker file
$CompletionMarker = @"
NICE DCV Installation Status
=============================
Timestamp: $(Get-Date)
Status: COMPLETED SUCCESSFULLY

DCV Configuration:
- DCV Server: Installed and running
- Port: $DCVPort
- Session Name: $DCVSessionName
- Web URL: https://<PUBLIC_IP>:$DCVPort
- Status: Active

Installation Paths:
- DCV Server: C:\Program Files\NICE\DCV\Server\
- DCV Config: C:\ProgramData\NICE\dcv\conf\
- Logs: $LogDir

Next Steps:
1. Ensure port $DCVPort is open in your security group
2. Open browser to https://<PUBLIC_IP>:$DCVPort
3. Accept the self-signed certificate warning
4. Login with Windows Administrator credentials
5. You should see the DCV session interface

Troubleshooting:
- Check logs in $LogDir for any errors
- Verify Windows Firewall allows port $DCVPort
- Ensure DCV Server service is running
"@

$CompletionMarker | Out-File -FilePath "$LogDir\dcv-install-complete.txt" -Encoding UTF8

# Create HTML status page
$WebPage = @"
<!DOCTYPE html>
<html>
<head>
    <title>NICE DCV Installation Status</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 40px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
        .container { background: white; border-radius: 10px; padding: 30px; box-shadow: 0 10px 30px rgba(0,0,0,0.2); }
        .status { padding: 20px; border-radius: 5px; margin: 10px 0; }
        .success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .info { background-color: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
        .warning { background-color: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
        h1 { color: #333; border-bottom: 3px solid #667eea; padding-bottom: 10px; }
        .dcv-section { background: linear-gradient(135deg, #667eea15 0%, #764ba215 100%); padding: 20px; border-radius: 8px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🖥️ NICE DCV Installation</h1>
        
        <div class="status success">
            <h2>✅ Installation Completed Successfully</h2>
            <p><strong>Timestamp:</strong> $(Get-Date)</p>
            <p><strong>Status:</strong> DCV is running and ready</p>
        </div>
        
        <div class="dcv-section">
            <h2>🖥️ NICE DCV Remote Access</h2>
            <p><strong>Status:</strong> ✅ Running</p>
            <p><strong>Web URL:</strong> https://[YOUR_PUBLIC_IP]:$DCVPort</p>
            <p><strong>Session:</strong> $DCVSessionName</p>
            <p><strong>Features:</strong> High-performance graphics, GPU acceleration, Low latency</p>
        </div>
        
        <div class="status info">
            <h3>📂 Installation Paths</h3>
            <p><strong>DCV Server:</strong> C:\Program Files\NICE\DCV\Server\</p>
            <p><strong>DCV Config:</strong> C:\ProgramData\NICE\dcv\conf\</p>
            <p><strong>Logs:</strong> $LogDir</p>
        </div>
        
        <div class="status warning">
            <h3>🚀 Next Steps</h3>
            <ol>
                <li>Ensure port $DCVPort is open in your security group</li>
                <li>Connect via NICE DCV using the web URL above</li>
                <li>Accept the self-signed certificate warning</li>
                <li>Login with Windows Administrator credentials</li>
                <li>You should see the DCV session interface</li>
            </ol>
        </div>
        
        <div class="status info">
            <h3>🔧 Troubleshooting</h3>
            <ul>
                <li>Check logs in $LogDir for any errors</li>
                <li>Verify Windows Firewall allows port $DCVPort</li>
                <li>Ensure DCV Server service is running</li>
                <li>Check security group rules in AWS Console</li>
            </ul>
        </div>
    </div>
</body>
</html>
"@

# Try to create the web status page
try {
    $WebPage | Out-File -FilePath "C:\inetpub\wwwroot\dcv-status.html" -Encoding UTF8
    Write-Host "✅ Web status page created at C:\inetpub\wwwroot\dcv-status.html" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Could not create web status page (IIS not installed)" -ForegroundColor Yellow
}

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "NICE DCV installation completed successfully!" -ForegroundColor Green
Write-Host "DCV is accessible at: https://<PUBLIC_IP>:$DCVPort" -ForegroundColor Yellow
Write-Host "Check $LogDir\dcv-install-complete.txt for details." -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green

# Stop transcript
Stop-Transcript

Write-Host "Full DCV installation script execution completed!" -ForegroundColor Green
</powershell>
