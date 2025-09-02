<powershell>
# AMI Builder User Data Script
# This script is specifically designed for building a custom AMI with Visual Studio Community 2022 and Nice DCV
# It will be run once during AMI creation and should complete all installations

# Set execution policy to allow script execution
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# Enable Windows features
Write-Host "Enabling Windows features..." -ForegroundColor Green
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart

# Create log directory
$LogDir = "C:\logs"
New-Item -ItemType Directory -Force -Path $LogDir
Start-Transcript -Path "$LogDir\ami-builder-setup.log" -Append

Write-Host "Starting AMI Builder setup..." -ForegroundColor Green
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Yellow

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
Write-Host "Installing Visual Studio 2022 Community..." -ForegroundColor Green
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
$DCVVersion = "2023.2-15773"
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

# Install DCV Virtual Display Driver
Write-Host "Installing DCV Virtual Display Driver..." -ForegroundColor Yellow
Start-Process msiexec.exe -ArgumentList "/i `"$DCVDisplayMSI`" /quiet /norestart /l*v `"$LogDir\dcv-display-install.log`"" -Wait

# Configure DCV
Write-Host "Configuring DCV..." -ForegroundColor Yellow

# Create DCV configuration directory
$DCVConfigDir = "C:\ProgramData\Nice\DCV\server\config"
New-Item -ItemType Directory -Force -Path $DCVConfigDir

# Create DCV server configuration
$DCVConfig = @"
# DCV Server Configuration for AMI Builder
# This configuration will be customized per deployment

# Basic settings
port = 8443
bind = 0.0.0.0
max-connections = 10
max-displays = 4

# Security settings
authentication = none
enable-raw-input = true
enable-pointer-sending = true

# Performance settings
enable-gpu-acceleration = true
enable-vsync = true
enable-hardware-encoding = true

# Logging
log-level = info
log-file = C:\logs\dcv-server.log

# Session management
session-management = internal
"@

$DCVConfig | Out-File -FilePath "$DCVConfigDir\dcv.conf" -Encoding ASCII

# Create DCV service configuration
$DCVServiceConfig = @"
# DCV Service Configuration
# This file configures the DCV service for automatic startup

[Unit]
Description=NICE DCV Server
After=network.target

[Service]
Type=simple
ExecStart=C:\Program Files\Nice\DCV\server\bin\dcv-server.exe
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
"@

$DCVServiceConfig | Out-File -FilePath "$DCVConfigDir\dcv.service" -Encoding ASCII

# ═══════════════════════════════════════════════════════════════════════════════
# Unreal Engine 5 Development Tools Installation
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Installing Unreal Engine 5 development tools..." -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# Install additional development tools
Write-Host "Installing additional development tools..." -ForegroundColor Green
choco install vcredist140 -y  # Visual C++ Redistributable
choco install vcredist2015 -y # Visual C++ Redistributable 2015
choco install vcredist2017 -y # Visual C++ Redistributable 2017
choco install vcredist2019 -y # Visual C++ Redistributable 2019
choco install vcredist2022 -y # Visual C++ Redistributable 2022

# Install build tools
choco install ninja -y
choco install make -y
choco install gnuwin32-coreutils -y

# Install Python packages for Unreal Engine
Write-Host "Installing Python packages..." -ForegroundColor Green
python -m pip install --upgrade pip
python -m pip install requests
python -m pip install boto3
python -m pip install awscli

# ═══════════════════════════════════════════════════════════════════════════════
# System Optimization and Configuration
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Optimizing system for Unreal Engine development..." -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# Configure Windows for development
Write-Host "Configuring Windows for development..." -ForegroundColor Yellow

# Set performance options
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 3a0daa51-3efe-4f60-8cd0-0e2b5e427a0a

# Disable hibernation to free up disk space
powercfg /hibernate off

# Configure Windows Defender exclusions for development
Write-Host "Configuring Windows Defender exclusions..." -ForegroundColor Yellow
Add-MpPreference -ExclusionPath "C:\logs"
Add-MpPreference -ExclusionPath "C:\dcv-install"
Add-MpPreference -ExclusionPath "C:\Program Files\Epic Games"
Add-MpPreference -ExclusionPath "C:\Users\Administrator\Documents\Unreal Projects"

# ═══════════════════════════════════════════════════════════════════════════════
# Final Configuration and Cleanup
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Finalizing AMI configuration..." -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# Create completion marker
$CompletionMarker = "C:\ami-builder-complete.txt"
$CompletionInfo = @"
AMI Builder Setup Completed Successfully
========================================
Timestamp: $(Get-Date)
Components Installed:
- Windows Server 2022
- Visual Studio Community 2022
- Nice DCV Server
- Development Tools (Git, Python, CMake, etc.)
- Unreal Engine 5 Development Environment

Next Steps:
1. Verify all installations
2. Test DCV connectivity
3. Create AMI from this instance
4. Clean up temporary files

Log Files:
- Main Setup: C:\logs\ami-builder-setup.log
- DCV Server: C:\logs\dcv-server-install.log
- DCV Display: C:\logs\dcv-display-install.log
"@

$CompletionInfo | Out-File -FilePath $CompletionMarker -Encoding ASCII

# Clean up temporary files
Write-Host "Cleaning up temporary files..." -ForegroundColor Green
Remove-Item -Path "$DCVDownloadDir" -Recurse -Force -ErrorAction SilentlyContinue

# Create startup script for DCV
$DCVStartupScript = @"
@echo off
echo Starting NICE DCV Server...
cd /d "C:\Program Files\Nice\DCV\server\bin"
dcv-server.exe --config "C:\ProgramData\Nice\DCV\server\config\dcv.conf"
pause
"@

$DCVStartupScript | Out-File -FilePath "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\start-dcv.bat" -Encoding ASCII

# Final status
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "AMI Builder setup completed successfully!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Yellow
Write-Host "Completion marker: $CompletionMarker" -ForegroundColor Yellow
Write-Host "Log files: $LogDir" -ForegroundColor Yellow
Write-Host "DCV configuration: $DCVConfigDir" -ForegroundColor Yellow

# Stop transcript
Stop-Transcript

# Signal completion to the AMI builder script
Write-Host "AMI_BUILDER_COMPLETE" -ForegroundColor Green
</powershell>
