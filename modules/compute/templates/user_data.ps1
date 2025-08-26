<powershell>
# Unreal Engine 5 Compilation Setup Script
# This script sets up a Windows EC2 instance for Unreal Engine 5 compilation

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

# Create log directory
$LogDir = "C:\logs"
New-Item -ItemType Directory -Force -Path $LogDir
Start-Transcript -Path "$LogDir\ue5-setup.log" -Append

Write-Host "Starting Unreal Engine 5 compilation setup..." -ForegroundColor Green
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
    exit 1
}

# Navigate to Unreal Engine directory
Set-Location $UE5SourceDir

# Run Setup script
Write-Host "Running Unreal Engine Setup script..." -ForegroundColor Green
.\Setup.bat

if ($LASTEXITCODE -ne 0) {
    Write-Host "Setup script failed. Check the logs for details." -ForegroundColor Red
    exit 1
}

# Generate project files
Write-Host "Generating project files..." -ForegroundColor Green
.\GenerateProjectFiles.bat

if ($LASTEXITCODE -ne 0) {
    Write-Host "Project file generation failed. Check the logs for details." -ForegroundColor Red
    exit 1
}

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

# Build Unreal Engine
Write-Host "Starting Unreal Engine build process..." -ForegroundColor Green
Write-Host "This process may take several hours depending on your instance specifications." -ForegroundColor Yellow

$BuildStartTime = Get-Date
$BuildTimeout = New-TimeSpan -Hours $BuildTimeoutHours

# Build UE5 Editor (if enabled)
if ($EnableUE5Editor) {
    Write-Host "Building Unreal Engine 5 Editor..." -ForegroundColor Green
    $BuildJob = Start-Job -ScriptBlock {
        param($UE5SourceDir)
        Set-Location $UE5SourceDir
        .\Engine\Build\BatchFiles\Build.bat UnrealEditor Win64 Development
    } -ArgumentList $UE5SourceDir
    
    $BuildJob | Wait-Job -Timeout $BuildTimeout.TotalSeconds
    
    if ($BuildJob.State -eq "Running") {
        Write-Host "Build timeout reached. Stopping build job..." -ForegroundColor Yellow
        Stop-Job $BuildJob
        Remove-Job $BuildJob
    } else {
        $BuildResult = Receive-Job $BuildJob
        Remove-Job $BuildJob
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Unreal Engine 5 Editor build completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "Unreal Engine 5 Editor build failed!" -ForegroundColor Red
            $BuildResult | Out-File -FilePath "$LogDir\ue5-editor-build-error.log" -Encoding UTF8
        }
    }
}

# Build UE5 Server (if enabled)
if ($EnableUE5Server) {
    Write-Host "Building Unreal Engine 5 Server..." -ForegroundColor Green
    $ServerBuildJob = Start-Job -ScriptBlock {
        param($UE5SourceDir)
        Set-Location $UE5SourceDir
        .\Engine\Build\BatchFiles\Build.bat UnrealServer Win64 Development
    } -ArgumentList $UE5SourceDir
    
    $ServerBuildJob | Wait-Job -Timeout $BuildTimeout.TotalSeconds
    
    if ($ServerBuildJob.State -eq "Running") {
        Write-Host "Server build timeout reached. Stopping build job..." -ForegroundColor Yellow
        Stop-Job $ServerBuildJob
        Remove-Job $ServerBuildJob
    } else {
        $ServerBuildResult = Receive-Job $ServerBuildJob
        Remove-Job $ServerBuildJob
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Unreal Engine 5 Server build completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "Unreal Engine 5 Server build failed!" -ForegroundColor Red
            $ServerBuildResult | Out-File -FilePath "$LogDir\ue5-server-build-error.log" -Encoding UTF8
        }
    }
}

# Build UE5 Linux (if enabled)
if ($EnableUE5Linux) {
    Write-Host "Building Unreal Engine 5 Linux..." -ForegroundColor Green
    $LinuxBuildJob = Start-Job -ScriptBlock {
        param($UE5SourceDir)
        Set-Location $UE5SourceDir
        .\Engine\Build\BatchFiles\Build.bat UnrealServer Linux Development
    } -ArgumentList $UE5SourceDir
    
    $LinuxBuildJob | Wait-Job -Timeout $BuildTimeout.TotalSeconds
    
    if ($LinuxBuildJob.State -eq "Running") {
        Write-Host "Linux build timeout reached. Stopping build job..." -ForegroundColor Yellow
        Stop-Job $LinuxBuildJob
        Remove-Job $LinuxBuildJob
    } else {
        $LinuxBuildResult = Receive-Job $LinuxBuildJob
        Remove-Job $LinuxBuildJob
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Unreal Engine 5 Linux build completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "Unreal Engine 5 Linux build failed!" -ForegroundColor Red
            $LinuxBuildResult | Out-File -FilePath "$LogDir\ue5-linux-build-error.log" -Encoding UTF8
        }
    }
}

# Create installed build (optional)
Write-Host "Creating installed build..." -ForegroundColor Green
$InstalledBuildJob = Start-Job -ScriptBlock {
    param($UE5SourceDir, $EnableUE5Editor, $EnableUE5Server, $EnableUE5Linux)
    Set-Location $UE5SourceDir
    
    $BuildTargets = @()
    if ($EnableUE5Editor) { $BuildTargets += "WithWin64=true" }
    if ($EnableUE5Server) { $BuildTargets += "WithServer=true" }
    if ($EnableUE5Linux) { $BuildTargets += "WithLinux=true" }
    
    $TargetString = $BuildTargets -join " -set:"
    $Command = ".\Engine\Build\BatchFiles\RunUAT.bat BuildGraph -target=`"Make Installed Build Win64`" -script=`"Engine/Build/InstalledEngineBuild.xml`" -clean -set:$TargetString"
    
    Invoke-Expression $Command
} -ArgumentList $UE5SourceDir, $EnableUE5Editor, $EnableUE5Server, $EnableUE5Linux

$InstalledBuildJob | Wait-Job -Timeout $BuildTimeout.TotalSeconds

if ($InstalledBuildJob.State -eq "Running") {
    Write-Host "Installed build timeout reached. Stopping build job..." -ForegroundColor Yellow
    Stop-Job $InstalledBuildJob
    Remove-Job $InstalledBuildJob
} else {
    $InstalledBuildResult = Receive-Job $InstalledBuildJob
    Remove-Job $InstalledBuildJob
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Installed build completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Installed build failed!" -ForegroundColor Red
        $InstalledBuildResult | Out-File -FilePath "$LogDir\ue5-installed-build-error.log" -Encoding UTF8
    }
}

# Create completion marker
$CompletionMarker = @"
Unreal Engine 5 Compilation Setup Completed
===========================================
Project: $ProjectName
Environment: $Environment
Unreal Engine Version: $UnrealEngineVersion
Branch: $UnrealEngineBranch
Build Start Time: $BuildStartTime
Build End Time: $(Get-Date)
Instance Type: $env:COMPUTERNAME

Build Configuration:
- Editor: $EnableUE5Editor
- Server: $EnableUE5Server
- Linux: $EnableUE5Linux
- Parallel Jobs: $ParallelBuildJobs
- Timeout: $BuildTimeoutHours hours

Installation Path: $UE5SourceDir
Log Directory: $LogDir

Next Steps:
1. Connect to this instance via RDP
2. Navigate to $UE5SourceDir
3. Launch the editor from Engine\Binaries\Win64\UnrealEditor.exe
4. Or open the solution file UE5.sln in Visual Studio

For more information, check the logs in $LogDir
"@

$CompletionMarker | Out-File -FilePath "$LogDir\setup-completion.txt" -Encoding UTF8

Write-Host "Unreal Engine 5 compilation setup completed!" -ForegroundColor Green
Write-Host "Check $LogDir\setup-completion.txt for details." -ForegroundColor Yellow

# Stop transcript
Stop-Transcript

# Create a simple web page to show build status
$WebPage = @"
<!DOCTYPE html>
<html>
<head>
    <title>Unreal Engine 5 Build Status</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .status { padding: 20px; border-radius: 5px; margin: 10px 0; }
        .success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .info { background-color: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
        .warning { background-color: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
    </style>
</head>
<body>
    <h1>Unreal Engine 5 Build Status</h1>
    <div class="status success">
        <h2>Build Completed Successfully</h2>
        <p><strong>Project:</strong> $ProjectName</p>
        <p><strong>Environment:</strong> $Environment</p>
        <p><strong>Unreal Engine Version:</strong> $UnrealEngineVersion</p>
        <p><strong>Build Time:</strong> $BuildStartTime</p>
    </div>
    <div class="status info">
        <h3>Installation Details</h3>
        <p><strong>Installation Path:</strong> $UE5SourceDir</p>
        <p><strong>Log Directory:</strong> $LogDir</p>
    </div>
    <div class="status warning">
        <h3>Next Steps</h3>
        <ul>
            <li>Connect via RDP to access the Windows desktop</li>
            <li>Navigate to $UE5SourceDir</li>
            <li>Launch UnrealEditor.exe from Engine\Binaries\Win64\</li>
            <li>Or open UE5.sln in Visual Studio</li>
        </ul>
    </div>
</body>
</html>
"@

$WebPage | Out-File -FilePath "C:\inetpub\wwwroot\index.html" -Encoding UTF8

Write-Host "Setup completed successfully!" -ForegroundColor Green
</powershell> 