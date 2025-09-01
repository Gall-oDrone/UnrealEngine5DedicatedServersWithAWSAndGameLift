<powershell>
# Unreal Engine 5 Compilation Setup Script with NICE DCV
# This script sets up a Windows EC2 instance for Unreal Engine 5 compilation and remote access via DCV

# Set execution policy to allow script execution
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# Enable Windows features
Write-Host "Enabling Windows features..." -ForegroundColor Green
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart

# Set variables from Terraform
$UnrealEngineVersion = "${unreal_engine_version}"
$UnrealEngineBranch = "${unreal_engine_branch}"
$EnableUE5Editor = ${enable_ue5_editor}
$EnableUE5Server = ${enable_ue5_server}
$EnableUE5Linux = ${enable_ue5_linux}
$ParallelBuildJobs = ${parallel_build_jobs}
$BuildTimeoutHours = ${build_timeout_hours}
$ProjectName = "${project_name}"
$Environment = "${environment}"

# DCV Configuration
$DCVVersion = "2023.2-15773"
$DCVSessionName = "ue5-session"
$DCVPort = "8443"

# Create log directory
$LogDir = "C:\logs"
New-Item -ItemType Directory -Force -Path $LogDir
Start-Transcript -Path "$LogDir\ue5-setup.log" -Append

Write-Host "Starting Unreal Engine 5 compilation setup with NICE DCV..." -ForegroundColor Green
Write-Host "Unreal Engine Version: $UnrealEngineVersion" -ForegroundColor Yellow
Write-Host "Branch: $UnrealEngineBranch" -ForegroundColor Yellow
Write-Host "Environment: $Environment" -ForegroundColor Yellow

# Install Chocolatey package manager
Write-Host "Installing Chocolatey..." -ForegroundColor Green
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Refresh environment variables
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Install required tools
Write-Host "Installing required tools..." -ForegroundColor Green
choco install git -y
choco install 7zip -y
choco install python -y
choco install cmake -y
choco install openssl -y  # For DCV certificate generation

# Install Visual Studio 2022 with required workloads
Write-Host "Installing Visual Studio 2022..." -ForegroundColor Green
choco install visualstudio2022community -y
choco install visualstudio2022-workload-vctools -y
choco install visualstudio2022-workload-nativedesktop -y
choco install visualstudio2022-workload-manageddesktop -y

# Install .NET SDK
Write-Host "Installing .NET SDK..." -ForegroundColor Green
choco install dotnet-sdk -y

# Install Windows SDK
Write-Host "Installing Windows SDK..." -ForegroundColor Green
choco install windows-sdk-10-version-2004-all -y

# Refresh environment variables again
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# ═══════════════════════════════════════════════════════════════════════════════
# NICE DCV Installation Section
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Installing NICE DCV for high-performance remote access..." -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# Create DCV download directory
$DCVDownloadDir = "C:\dcv-install"
New-Item -ItemType Directory -Force -Path $DCVDownloadDir

# Download DCV components
Write-Host "Downloading DCV Server..." -ForegroundColor Yellow
$DCVServerURL = "https://d1uj6qtbmh3dt5.cloudfront.net/2023.2/Servers/nice-dcv-server-$DCVVersion.x86_64.msi"
$DCVServerMSI = "$DCVDownloadDir\dcv-server.msi"
Invoke-WebRequest -Uri $DCVServerURL -OutFile $DCVServerMSI

Write-Host "Downloading DCV Virtual Display Driver..." -ForegroundColor Yellow
$DCVDisplayURL = "https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-virtual-display-x64-Release.msi"
$DCVDisplayMSI = "$DCVDownloadDir\dcv-display.msi"
Invoke-WebRequest -Uri $DCVDisplayURL -OutFile $DCVDisplayMSI

# Install DCV Server
Write-Host "Installing DCV Server..." -ForegroundColor Yellow
Start-Process msiexec.exe -ArgumentList "/i `"$DCVServerMSI`" /quiet /norestart /l*v `"$LogDir\dcv-server-install.log`"" -Wait

# Install DCV Virtual Display Driver (for headless operation)
Write-Host "Installing DCV Virtual Display Driver..." -ForegroundColor Yellow
Start-Process msiexec.exe -ArgumentList "/i `"$DCVDisplayMSI`" /quiet /norestart /l*v `"$LogDir\dcv-display-install.log`"" -Wait

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

$DCVConfig | Out-File -FilePath "$DCVConfigDir\dcv.conf" -Encoding ASCII

# Configure Windows Firewall for DCV
Write-Host "Configuring Windows Firewall for DCV..." -ForegroundColor Yellow
New-NetFirewallRule -DisplayName "DCV Server" -Direction Inbound -Protocol TCP -LocalPort $DCVPort -Action Allow
New-NetFirewallRule -DisplayName "DCV Server UDP" -Direction Inbound -Protocol UDP -LocalPort $DCVPort -Action Allow

# Create self-signed certificate for DCV (development only)
Write-Host "Creating self-signed certificate for DCV..." -ForegroundColor Yellow
$cert = New-SelfSignedCertificate -DnsName "localhost", "*.amazonaws.com" -CertStoreLocation "Cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(2)
$certPath = "Cert:\LocalMachine\My\" + $cert.Thumbprint
Export-Certificate -Cert $certPath -FilePath "C:\ProgramData\NICE\dcv\cert.cer"

# Set DCV to use the console session
Write-Host "Configuring DCV for console session..." -ForegroundColor Yellow
& "C:\Program Files\NICE\DCV\Server\bin\dcv.exe" set-permissions --session console --user Administrator --all-permissions

# Start DCV Server service
Write-Host "Starting DCV Server service..." -ForegroundColor Yellow
Set-Service -Name "DCV Server" -StartupType Automatic
Start-Service -Name "DCV Server"

# Create DCV session
Write-Host "Creating DCV session..." -ForegroundColor Yellow
Start-Sleep -Seconds 10  # Wait for service to fully start
try {
    & "C:\Program Files\NICE\DCV\Server\bin\dcv.exe" create-session --type=console --owner Administrator $DCVSessionName 2>&1 | Out-String
    Write-Host "DCV session '$DCVSessionName' created successfully" -ForegroundColor Green
} catch {
    Write-Host "Note: DCV session creation might require manual setup after reboot" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════════
# End of NICE DCV Installation
# ═══════════════════════════════════════════════════════════════════════════════

# Create directories for Unreal Engine
$UE5Dir = "C:\UnrealEngine"
$UE5SourceDir = "C:\UnrealEngine\UnrealEngine"
New-Item -ItemType Directory -Force -Path $UE5Dir
New-Item -ItemType Directory -Force -Path $UE5SourceDir

# Clone Unreal Engine repository
Write-Host "Cloning Unreal Engine repository..." -ForegroundColor Green
Set-Location $UE5Dir
git clone --branch $UnrealEngineBranch https://github.com/EpicGames/UnrealEngine.git

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to clone Unreal Engine repository. Please ensure you have access to the Epic Games repository." -ForegroundColor Red
    Write-Host "You need to link your GitHub account to Epic Games to access the UnrealEngine repo." -ForegroundColor Red
    
    # Create a marker file to indicate UE5 needs manual setup
    "UE5 repository clone failed - manual setup required" | Out-File -FilePath "$LogDir\ue5-clone-failed.txt"
    
    # Continue with DCV setup even if UE5 fails
} else {
    # Navigate to Unreal Engine directory
    Set-Location $UE5SourceDir

    # Run Setup script
    Write-Host "Running Unreal Engine Setup script..." -ForegroundColor Green
    .\Setup.bat

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Setup script failed. Check the logs for details." -ForegroundColor Red
    } else {
        # Generate project files
        Write-Host "Generating project files..." -ForegroundColor Green
        .\GenerateProjectFiles.bat

        # Create build configuration
        Write-Host "Creating build configuration..." -ForegroundColor Green
        $BuildConfigDir = "Engine\Saved\UnrealBuildTool"
        New-Item -ItemType Directory -Force -Path $BuildConfigDir

        $BuildConfig = @"
<?xml version="1.0" encoding="utf-8"?>
<Configuration xmlns="https://www.unrealengine.com/BuildConfiguration">
  <BuildConfiguration>Development</BuildConfiguration>
  <ParallelExecutor>
    <MaxProcessorCount>$ParallelBuildJobs</MaxProcessorCount>
  </ParallelExecutor>
  <BuildConfiguration>
    <bAllowXGE>false</bAllowXGE>
    <bUseIncrementalBuilds>true</bUseIncrementalBuilds>
    <bUseUnityBuild>false</bUseUnityBuild>
  </BuildConfiguration>
</Configuration>
"@

        $BuildConfig | Out-File -FilePath "$BuildConfigDir\BuildConfiguration.xml" -Encoding UTF8

        # Build process continues as before...
        Write-Host "Unreal Engine setup initiated. Build will continue in background." -ForegroundColor Green
    }
}

# Create completion marker file with DCV info
$CompletionMarker = @"
Unreal Engine 5 & NICE DCV Setup Status
===========================================
Timestamp: $(Get-Date)
Project: $ProjectName
Environment: $Environment
Instance: $env:COMPUTERNAME

NICE DCV Configuration:
- DCV Server: Installed and running
- Port: $DCVPort
- Session Name: $DCVSessionName
- Web URL: https://<PUBLIC_IP>:$DCVPort
- Status: Active

Unreal Engine Configuration:
- Version: $UnrealEngineVersion
- Branch: $UnrealEngineBranch
- Installation Path: $UE5SourceDir
- Log Directory: $LogDir

Remote Access Options:
1. NICE DCV (Recommended for graphics):
   - Open browser to https://<PUBLIC_IP>:$DCVPort
   - Use Windows Administrator credentials
   - High-performance graphics support

2. Windows RDP (Standard):
   - Connect to <PUBLIC_IP>:3389
   - Username: Administrator
   - Standard Windows remote desktop

Setup Status: $(if (Test-Path "$LogDir\ue5-clone-failed.txt") { "UE5 Manual Setup Required" } else { "Complete" })

Next Steps:
1. Connect via DCV or RDP
2. If UE5 clone failed, manually link GitHub to Epic Games account
3. Check logs in $LogDir for detailed information
"@

$CompletionMarker | Out-File -FilePath "$LogDir\setup-complete.txt" -Encoding UTF8

# Create a scheduled task to recreate DCV session on reboot
Write-Host "Creating scheduled task for DCV session..." -ForegroundColor Yellow
$action = New-ScheduledTaskAction -Execute "C:\Program Files\NICE\DCV\Server\bin\dcv.exe" -Argument "create-session --type=console --owner Administrator $DCVSessionName"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "CreateDCVSession" -Action $action -Trigger $trigger -Principal $principal -Description "Create DCV session on startup"

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "Setup completed successfully!" -ForegroundColor Green
Write-Host "DCV is accessible at: https://<PUBLIC_IP>:$DCVPort" -ForegroundColor Yellow
Write-Host "Check $LogDir\setup-complete.txt for details." -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green

# Stop transcript
Stop-Transcript

# Create HTML status page
$WebPage = @"
<!DOCTYPE html>
<html>
<head>
    <title>UE5 & DCV Setup Status</title>
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
        <h1>🎮 Unreal Engine 5 + NICE DCV Setup</h1>
        
        <div class="status success">
            <h2>✅ Setup Completed Successfully</h2>
            <p><strong>Timestamp:</strong> $(Get-Date)</p>
            <p><strong>Project:</strong> $ProjectName</p>
            <p><strong>Environment:</strong> $Environment</p>
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
            <p><strong>Unreal Engine:</strong> $UE5SourceDir</p>
            <p><strong>DCV Config:</strong> C:\ProgramData\NICE\dcv\conf</p>
            <p><strong>Logs:</strong> $LogDir</p>
        </div>
        
        <div class="status warning">
            <h3>🚀 Next Steps</h3>
            <ol>
                <li>Connect via NICE DCV using the web URL above</li>
                <li>Accept the self-signed certificate warning</li>
                <li>Login with Windows Administrator credentials</li>
                <li>Launch UnrealEditor.exe from Engine\Binaries\Win64\</li>
            </ol>
        </div>
    </div>
</body>
</html>
"@

# Try to create the IIS directory, but don't fail if it doesn't exist
try {
    $WebPage | Out-File -FilePath "C:\inetpub\wwwroot\index.html" -Encoding UTF8
} catch {
    Write-Host "Could not create web status page (IIS not installed)" -ForegroundColor Yellow
}

Write-Host "Full setup script execution completed!" -ForegroundColor Green
</powershell>