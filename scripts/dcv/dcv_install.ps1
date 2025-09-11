# DCV Installation Script for Windows via SSM
# Following AWS Documentation Best Practices

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# Create log directory
$LogDir = "C:\logs"
New-Item -ItemType Directory -Force -Path $LogDir -ErrorAction SilentlyContinue
Start-Transcript -Path "$LogDir\dcv-install.log" -Append

Write-Host "Starting NICE DCV Installation..." -ForegroundColor Green

# Install prerequisites with Chocolatey
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

# Install Visual C++ Redistributables (required for DCV 2024.0)
Write-Host "Installing Visual C++ Redistributables..." -ForegroundColor Yellow
choco install -y --no-progress vcredist-all

# Download DCV
$DCVDownloadDir = "C:\dcv-install"
New-Item -ItemType Directory -Force -Path $DCVDownloadDir

# Use latest version URLs
$DCVServerURL = "https://d1uj6qtbmh3dt5.cloudfront.net/2024.0/Clients/nice-dcv-client-Release-2024.0-9431.msi"
$DCVDisplayURL = "https://d1uj6qtbmh3dt5.cloudfront.net/Drivers/nice-dcv-virtual-display-x64-Release-88.msi"

$DCVServerMSI = "$DCVDownloadDir\dcv-server.msi"
$DCVDisplayMSI = "$DCVDownloadDir\dcv-display.msi"

Write-Host "Downloading DCV Server..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $DCVServerURL -OutFile $DCVServerMSI -UseBasicParsing

# Check if we need the Virtual Display Driver
# Not needed for Windows Server 2019+ with DCV 2023.1+, but useful for Windows Server 2016
$OSVersion = [System.Environment]::OSVersion.Version
$NeedVirtualDisplay = $false

if ($OSVersion.Major -eq 10 -and $OSVersion.Build -lt 17763) {
    # Windows Server 2016 (build < 17763)
    $NeedVirtualDisplay = $true
    Write-Host "Windows Server 2016 detected - Installing Virtual Display Driver..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $DCVDisplayURL -OutFile $DCVDisplayMSI -UseBasicParsing
}

# Set the session owner
# When running via SSM, we're SYSTEM, so we need to explicitly set Administrator
$SessionOwner = "Administrator"

Write-Host "Installing DCV Server with automatic session owner: $SessionOwner" -ForegroundColor Yellow

# Install DCV Server with all components and automatic session configuration
# Using official MSI parameters from AWS documentation
$msiArgs = @(
    "/i", "`"$DCVServerMSI`"",
    "AUTOMATIC_SESSION_OWNER=$SessionOwner",  # Set the console session owner
    "ADDLOCAL=ALL",                           # Install all components
    "/quiet",
    "/norestart",
    "/l*v", "`"$LogDir\dcv-server-msi.log`""
)

Write-Host "Running: msiexec.exe $($msiArgs -join ' ')" -ForegroundColor Cyan
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru

Write-Host "DCV Server install exit code: $($process.ExitCode)" -ForegroundColor Yellow

# Install Virtual Display Driver if needed (for Windows Server 2016)
if ($NeedVirtualDisplay) {
    Write-Host "Installing DCV Virtual Display Driver..." -ForegroundColor Yellow
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$DCVDisplayMSI`" /quiet /norestart /l*v `"$LogDir\dcv-display-msi.log`"" -Wait
}

# Wait for service to initialize
Start-Sleep -Seconds 10

# Verify service status
$service = Get-Service "DCV Server" -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "DCV Service Status: $($service.Status)" -ForegroundColor Green
    
    if ($service.Status -ne 'Running') {
        Write-Host "Starting DCV Service..." -ForegroundColor Yellow
        Start-Service -Name "DCV Server" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }
}

# Verify DCV installation and sessions
$DCVPath = "C:\Program Files\NICE\DCV\Server\bin\dcv.exe"
if (Test-Path $DCVPath) {
    Write-Host "Checking DCV sessions..." -ForegroundColor Yellow
    
    try {
        # List existing sessions
        $sessions = & $DCVPath list-sessions 2>&1
        Write-Host "Current DCV sessions:" -ForegroundColor Green
        Write-Host $sessions
        
        # Check if console session exists
        if ($sessions -notmatch "console") {
            Write-Host "No console session found. The automatic session should have been created." -ForegroundColor Yellow
            Write-Host "Attempting to create one manually..." -ForegroundColor Yellow
            
            $createResult = & $DCVPath create-session --type console --owner $SessionOwner --name "Console Session" console 2>&1
            Write-Host "Session creation result: $createResult" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "Error checking sessions: $_" -ForegroundColor Red
    }
}

# Display network status
Write-Host "`nNetwork Status:" -ForegroundColor Green
$ports = netstat -an | findstr :8443
Write-Host $ports

# Display firewall rules
Write-Host "`nFirewall Rules:" -ForegroundColor Green
Get-NetFirewallRule -DisplayName "DCV*" | Select-Object DisplayName, Enabled, Direction, Action | Format-Table

# Get instance metadata for connection info
try {
    $instanceId = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/instance-id -TimeoutSec 2
    $publicIP = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/public-ipv4 -TimeoutSec 2
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "DCV Installation Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Instance ID: $instanceId" -ForegroundColor Yellow
    Write-Host "Connection URL: https://${publicIP}:8443" -ForegroundColor Yellow
    Write-Host "Username: $SessionOwner" -ForegroundColor Yellow
    Write-Host "Password: Retrieved from Systems Manager Parameter Store" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
} catch {
    Write-Host "`nDCV Installation Complete!" -ForegroundColor Green
    Write-Host "Connect using: https://<instance-public-ip>:8443" -ForegroundColor Yellow
    Write-Host "Username: $SessionOwner" -ForegroundColor Yellow
}

Stop-Transcript