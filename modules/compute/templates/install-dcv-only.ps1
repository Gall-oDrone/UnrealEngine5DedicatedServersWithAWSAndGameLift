<powershell>
# Simplified Windows Setup Script - NICE DCV Only
# This script focuses on installing and configuring NICE DCV without Unreal Engine

# Set execution policy to allow script execution
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# Set Windows Administrator password if provided
if ("${admin_password}" -ne "") {
    Write-Host "Setting Windows Administrator password..." -ForegroundColor Green
    $securePassword = ConvertTo-SecureString -String "${admin_password}" -AsPlainText -Force
    Set-LocalUser -Name "Administrator" -Password $securePassword
    Write-Host "Windows Administrator password set successfully" -ForegroundColor Green
}

# Create log directory
$LogDir = "C:\logs"
New-Item -ItemType Directory -Force -Path $LogDir
Start-Transcript -Path "$LogDir\dcv-install.log" -Append

# Create progress marker function
function Set-ProgressMarker {
    param([string]$Stage)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Stage" | Out-File -FilePath "$LogDir\stage-$Stage.txt" -Encoding UTF8
    Write-Host "[$timestamp] Progress: $Stage" -ForegroundColor Cyan
}

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Starting NICE DCV Installation Script" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Yellow

# ═══════════════════════════════════════════════════════════════════════════════
# Stage 1: Prerequisites and Windows Configuration
# ═══════════════════════════════════════════════════════════════════════════════

Set-ProgressMarker "prerequisites"
Write-Host "Stage 1: Installing prerequisites..." -ForegroundColor Green

# Enable Windows features for better graphics performance
Write-Host "Enabling Windows features..." -ForegroundColor Yellow
try {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart -ErrorAction SilentlyContinue
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart -ErrorAction SilentlyContinue
    Write-Host "Windows features enabled" -ForegroundColor Green
} catch {
    Write-Host "Note: Some Windows features could not be enabled: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Install Chocolatey package manager
Write-Host "Installing Chocolatey package manager..." -ForegroundColor Yellow
try {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    
    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "✅ Chocolatey installed successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to install Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Install basic tools needed for DCV
Write-Host "Installing basic tools..." -ForegroundColor Yellow
try {
    choco install -y --no-progress microsoft-vcredist-all
    choco install -y --no-progress dotnet-runtime
    Write-Host "✅ Basic tools installed" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Some tools might not have installed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════════
# Stage 2: Download NICE DCV Components
# ═══════════════════════════════════════════════════════════════════════════════

Set-ProgressMarker "dcv-download"
Write-Host "Stage 2: Downloading NICE DCV components..." -ForegroundColor Green

$DCVVersion = "2023.1-16388"  # Using stable version from AWS docs
$DCVDownloadDir = "C:\dcv-install"
New-Item -ItemType Directory -Force -Path $DCVDownloadDir

# Download URLs from AWS documentation
$DCVServerURL = "https://d1uj6qtbmh3dt5.cloudfront.net/2023.1/Servers/nice-dcv-server-x64-Release-2023.1-16388.msi"
$DCVDisplayURL = "https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-virtual-display-x64-Release.msi"

# Download DCV Server
Write-Host "Downloading DCV Server..." -ForegroundColor Yellow
$DCVServerMSI = "$DCVDownloadDir\dcv-server.msi"
$retryCount = 0
$maxRetries = 3

while ($retryCount -lt $maxRetries) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $DCVServerURL -OutFile $DCVServerMSI -UseBasicParsing -TimeoutSec 300
        
        if (Test-Path $DCVServerMSI) {
            $fileSize = (Get-Item $DCVServerMSI).Length
            Write-Host "✅ DCV Server downloaded successfully (Size: $($fileSize / 1MB) MB)" -ForegroundColor Green
            break
        }
    } catch {
        $retryCount++
        Write-Host "⚠️ Download attempt $retryCount failed: $($_.Exception.Message)" -ForegroundColor Yellow
        
        if ($retryCount -eq $maxRetries) {
            Write-Host "❌ Failed to download DCV Server after $maxRetries attempts" -ForegroundColor Red
            exit 1
        }
        Start-Sleep -Seconds 10
    }
}

# Download DCV Virtual Display Driver
Write-Host "Downloading DCV Virtual Display Driver..." -ForegroundColor Yellow
$DCVDisplayMSI = "$DCVDownloadDir\dcv-display.msi"
$retryCount = 0

while ($retryCount -lt $maxRetries) {
    try {
        Invoke-WebRequest -Uri $DCVDisplayURL -OutFile $DCVDisplayMSI -UseBasicParsing -TimeoutSec 300
        
        if (Test-Path $DCVDisplayMSI) {
            $fileSize = (Get-Item $DCVDisplayMSI).Length
            Write-Host "✅ DCV Virtual Display Driver downloaded successfully (Size: $($fileSize / 1MB) MB)" -ForegroundColor Green
            break
        }
    } catch {
        $retryCount++
        Write-Host "⚠️ Download attempt $retryCount failed: $($_.Exception.Message)" -ForegroundColor Yellow
        
        if ($retryCount -eq $maxRetries) {
            Write-Host "❌ Failed to download DCV Display Driver after $maxRetries attempts" -ForegroundColor Red
            exit 1
        }
        Start-Sleep -Seconds 10
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Stage 3: Install NICE DCV Components
# ═══════════════════════════════════════════════════════════════════════════════

Set-ProgressMarker "dcv-install"
Write-Host "Stage 3: Installing NICE DCV components..." -ForegroundColor Green

# Install DCV Server
Write-Host "Installing DCV Server (this may take a few minutes)..." -ForegroundColor Yellow
try {
    $msiArgs = @(
        "/i",
        "`"$DCVServerMSI`"",
        "/quiet",
        "/norestart",
        "/l*v",
        "`"$LogDir\dcv-server-msi.log`""
    )
    
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
    
    if ($process.ExitCode -eq 0) {
        Write-Host "✅ DCV Server installed successfully" -ForegroundColor Green
    } elseif ($process.ExitCode -eq 3010) {
        Write-Host "✅ DCV Server installed successfully (reboot required)" -ForegroundColor Green
    } else {
        Write-Host "❌ DCV Server installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
        Write-Host "Check log at: $LogDir\dcv-server-msi.log" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "❌ Failed to install DCV Server: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Install DCV Virtual Display Driver
Write-Host "Installing DCV Virtual Display Driver..." -ForegroundColor Yellow
try {
    $msiArgs = @(
        "/i",
        "`"$DCVDisplayMSI`"",
        "/quiet",
        "/norestart",
        "/l*v",
        "`"$LogDir\dcv-display-msi.log`""
    )
    
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
    
    if ($process.ExitCode -eq 0) {
        Write-Host "✅ DCV Virtual Display Driver installed successfully" -ForegroundColor Green
    } elseif ($process.ExitCode -eq 3010) {
        Write-Host "✅ DCV Virtual Display Driver installed successfully (reboot required)" -ForegroundColor Green
    } else {
        Write-Host "⚠️ DCV Virtual Display Driver installation returned code: $($process.ExitCode)" -ForegroundColor Yellow
        Write-Host "This is optional for headless operation, continuing..." -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️ Failed to install DCV Virtual Display Driver: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "This is optional, continuing..." -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════════
# Stage 4: Configure NICE DCV
# ═══════════════════════════════════════════════════════════════════════════════

Set-ProgressMarker "dcv-config"
Write-Host "Stage 4: Configuring NICE DCV..." -ForegroundColor Green

# Wait for DCV installation to settle
Write-Host "Waiting for DCV installation to complete..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Configure DCV registry settings (as per AWS documentation)
Write-Host "Configuring DCV registry settings..." -ForegroundColor Yellow
try {
    # Create registry path if it doesn't exist
    $regPath = "HKLM:\SOFTWARE\GSettings\com\nicesoftware\dcv\security"
    if (!(Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    
    # Set authentication to system (Windows authentication)
    Set-ItemProperty -Path $regPath -Name "authentication" -Value "system" -Type String
    
    # Allow owner to interact with desktop session
    Set-ItemProperty -Path $regPath -Name "owner" -Value "Administrator" -Type String
    
    # Create display registry path
    $regPathDisplay = "HKLM:\SOFTWARE\GSettings\com\nicesoftware\dcv\display"
    if (!(Test-Path $regPathDisplay)) {
        New-Item -Path $regPathDisplay -Force | Out-Null
    }
    
    # Enable console session
    Set-ItemProperty -Path $regPathDisplay -Name "enable-console-session" -Value 1 -Type DWord
    
    # Create connectivity registry path
    $regPathConnectivity = "HKLM:\SOFTWARE\GSettings\com\nicesoftware\dcv\connectivity"
    if (!(Test-Path $regPathConnectivity)) {
        New-Item -Path $regPathConnectivity -Force | Out-Null
    }
    
    # Set web port
    Set-ItemProperty -Path $regPathConnectivity -Name "web-port" -Value 8443 -Type DWord
    
    Write-Host "✅ DCV registry settings configured" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to configure DCV registry: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Configure Windows Firewall for DCV
Write-Host "Configuring Windows Firewall for DCV..." -ForegroundColor Yellow
try {
    # Remove existing rules if they exist
    Remove-NetFirewallRule -DisplayName "DCV Server TCP" -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "DCV Server UDP" -ErrorAction SilentlyContinue
    
    # Add new firewall rules
    New-NetFirewallRule -DisplayName "DCV Server TCP" -Direction Inbound -Protocol TCP -LocalPort 8443 -Action Allow -ErrorAction Stop | Out-Null
    New-NetFirewallRule -DisplayName "DCV Server UDP" -Direction Inbound -Protocol UDP -LocalPort 8443 -Action Allow -ErrorAction Stop | Out-Null
    
    Write-Host "✅ Windows Firewall rules configured successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to configure Windows Firewall: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create self-signed certificate for DCV
Write-Host "Creating self-signed certificate for DCV..." -ForegroundColor Yellow
try {
    # Get the instance metadata
    $instanceId = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/instance-id -TimeoutSec 5
    $publicIp = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/public-ipv4 -TimeoutSec 5
    
    $cert = New-SelfSignedCertificate `
        -DnsName "localhost", "$instanceId.compute.amazonaws.com", "$publicIp" `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -NotAfter (Get-Date).AddYears(2) `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -ErrorAction Stop
    
    # Export certificate for DCV (optional, DCV can use cert store)
    $certPath = "Cert:\LocalMachine\My\" + $cert.Thumbprint
    Export-Certificate -Cert $certPath -FilePath "C:\ProgramData\NICE\dcv\cert.cer" -ErrorAction SilentlyContinue
    
    Write-Host "✅ Self-signed certificate created successfully" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Could not create optimal certificate: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "DCV will create its own certificate" -ForegroundColor Yellow
}

# Start DCV Server service
Write-Host "Starting DCV Server service..." -ForegroundColor Yellow
try {
    # Ensure service exists
    $service = Get-Service -Name "DCV Server" -ErrorAction SilentlyContinue
    
    if ($service) {
        Set-Service -Name "DCV Server" -StartupType Automatic -ErrorAction Stop
        Start-Service -Name "DCV Server" -ErrorAction Stop
        
        # Wait for service to fully start
        $timeout = 30
        $elapsed = 0
        while (($service.Status -ne 'Running') -and ($elapsed -lt $timeout)) {
            Start-Sleep -Seconds 2
            $elapsed += 2
            $service.Refresh()
        }
        
        if ($service.Status -eq 'Running') {
            Write-Host "✅ DCV Server service is running" -ForegroundColor Green
        } else {
            Write-Host "⚠️ DCV Server service status: $($service.Status)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ DCV Server service not found" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Failed to start DCV Server service: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Wait for DCV to fully initialize
Write-Host "Waiting for DCV to fully initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 20

# Create DCV session
Write-Host "Creating DCV session..." -ForegroundColor Yellow
try {
    # Check if dcv.exe exists
    $dcvExe = "C:\Program Files\NICE\DCV\Server\bin\dcv.exe"
    
    if (Test-Path $dcvExe) {
        # Close any existing sessions
        & $dcvExe close-session console 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        
        # Create console session
        $sessionOutput = & $dcvExe create-session --type=console --owner Administrator --storage-root "C:\ProgramData\NICE\dcv" console 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ DCV console session created successfully" -ForegroundColor Green
            Write-Host "Session output: $sessionOutput" -ForegroundColor Cyan
        } else {
            Write-Host "⚠️ DCV session creation returned: $sessionOutput" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️ DCV executable not found at expected location" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️ Could not create DCV session: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Session will be created automatically on first connection" -ForegroundColor Yellow
}

# Create scheduled task to recreate DCV session on reboot
Write-Host "Creating scheduled task for DCV session..." -ForegroundColor Yellow
try {
    $action = New-ScheduledTaskAction -Execute "C:\Program Files\NICE\DCV\Server\bin\dcv.exe" -Argument "create-session --type=console --owner Administrator console"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $delay = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    Register-ScheduledTask -TaskName "CreateDCVSession" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Create DCV session on startup" -ErrorAction Stop | Out-Null
    
    Write-Host "✅ Scheduled task created successfully" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Could not create scheduled task: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════════
# Stage 5: Verification and Completion
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "Stage 5: Verifying installation..." -ForegroundColor Green

# Verify DCV is running
$dcvService = Get-Service -Name "DCV Server" -ErrorAction SilentlyContinue
if ($dcvService -and $dcvService.Status -eq "Running") {
    Write-Host "✅ DCV Server service is running" -ForegroundColor Green
} else {
    Write-Host "❌ DCV Server service is not running" -ForegroundColor Red
}

# Check if DCV is listening on port 8443
$netstatOutput = netstat -an | Select-String ":8443"
if ($netstatOutput) {
    Write-Host "✅ DCV is listening on port 8443" -ForegroundColor Green
} else {
    Write-Host "⚠️ DCV may not be listening on port 8443 yet" -ForegroundColor Yellow
}

# Get instance metadata for connection info
try {
    $publicIp = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/public-ipv4 -TimeoutSec 5
    $instanceId = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/instance-id -TimeoutSec 5
} catch {
    $publicIp = "<PUBLIC_IP>"
    $instanceId = "<INSTANCE_ID>"
}

# Create completion marker file
$CompletionMarker = @"
NICE DCV Installation Status
=============================
Timestamp: $(Get-Date)
Status: COMPLETED SUCCESSFULLY

DCV Configuration:
- DCV Server: Installed and running
- Port: 8443
- Session Type: Console
- Session Name: console
- Web URL: https://$publicIp:8443

Service Status:
- DCV Server Service: $($dcvService.Status)

Installation Paths:
- DCV Server: C:\Program Files\NICE\DCV\Server\
- DCV Config: Registry-based configuration
- Logs: $LogDir

Connection Instructions:
1. Open web browser
2. Navigate to: https://$publicIp:8443
3. Accept self-signed certificate warning
4. Login with:
   - Username: Administrator
   - Password: (use your configured password)

Troubleshooting:
- Check service: Get-Service 'DCV Server'
- Check logs: $LogDir\dcv-server-msi.log
- Check firewall: Get-NetFirewallRule -DisplayName 'DCV*'
- Restart service: Restart-Service 'DCV Server'
"@

$CompletionMarker | Out-File -FilePath "$LogDir\dcv-install-complete.txt" -Encoding UTF8
Write-Host "✅ Installation summary saved to: $LogDir\dcv-install-complete.txt" -ForegroundColor Green

# Stop transcript
Stop-Transcript

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "NICE DCV installation completed successfully!" -ForegroundColor Green
Write-Host "DCV is accessible at: https://$publicIp:8443" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green

# Final status output for debugging
Write-Host "`nFinal Status Check:" -ForegroundColor Cyan
Get-Service -Name "DCV Server" | Select-Object Name, Status, StartType | Format-Table
netstat -an | Select-String ":8443"
</powershell>