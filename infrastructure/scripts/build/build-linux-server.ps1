<#
.SYNOPSIS
  Builds, cooks and stages the FrontendUI Linux dedicated server on the UE 5.6 build box,
  then uploads the staged build to S3. Runs unattended under SSM (AWS-RunPowerShellScript)
  or interactively in an elevated PowerShell.

.DESCRIPTION
  Steps:
    1. Bring the restored data volume online and locate the UE 5.6 source build
       (Engine\Build\BatchFiles\RunUAT.bat) on it.
    2. Make sure the Linux cross-compile toolchain for UE 5.6 (v25, clang 18.1.0) is
       installed; install it silently from Epic's CDN if not.
    3. Clone or update the game repository at the requested ref.
    4. RunUAT BuildCookRun -platform=Linux -server (and optionally -platform=Win64 -server).
    5. Zip Saved\StagedBuilds\LinuxServer and upload zip + log to s3://<bucket>/builds/.

  Writes progress to C:\ue5-build\build-<timestamp>.log and a final JSON summary to
  C:\ue5-build\last-build.json. Prints only short status lines to stdout so the SSM
  command output stays readable.

.PARAMETER RepoUrl      Git URL of the game project.
.PARAMETER Ref          Branch or tag to build (default master).
.PARAMETER ProjectName  .uproject name without extension (default FrontendUI).
.PARAMETER S3Bucket     Artifacts bucket. Empty = skip upload.
.PARAMETER AlsoWindows  Also build/stage the Win64 server (for LaunchDedicatedServer.bat PACKAGED).
.PARAMETER SkipCook     Build the server binary only (quick compile check).
#>
[CmdletBinding()]
param(
    [string]$RepoUrl     = "https://github.com/Gall-oDrone/Tutorial-FrontendUI-Experience-In-UnrealEngine-5-Using-C-And-Common-UI.git",
    [string]$Ref         = "master",
    [string]$ProjectName = "FrontendUI",
    [string]$S3Bucket    = "ue5-artifacts-326105557351-us-east-1",
    [string]$ProjectsRoot = "",
    [switch]$AlsoWindows,
    [switch]$SkipCook
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"
$Stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$WorkDir = "C:\ue5-build"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$LogFile = Join-Path $WorkDir "build-$Stamp.log"
$Summary = [ordered]@{ Started = (Get-Date).ToString("o"); Status = "running"; Steps = @() }

function Log([string]$Msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Msg
    $line | Tee-Object -FilePath $LogFile -Append | Write-Output
}
function Step([string]$Name) { $script:Summary.Steps += $Name; Log "== $Name" }
function Finish([string]$Status, [string]$Message = "") {
    $Summary.Status   = $Status
    $Summary.Message  = $Message
    $Summary.Finished = (Get-Date).ToString("o")
    $Summary.Log      = $LogFile
    $Summary | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $WorkDir "last-build.json") -Encoding utf8
    Log "RESULT: $Status $Message"
    if ($S3Bucket) {
        try { & $script:Aws s3 cp $LogFile "s3://$S3Bucket/builds/logs/" --only-show-errors | Out-Null } catch {}
    }
    if ($Status -ne "ok") { exit 1 }
}

# ---------------------------------------------------------------------------------
Step "Tools"
$Aws = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
if (-not (Test-Path $Aws)) { $Aws = (Get-Command aws -ErrorAction SilentlyContinue).Source }
if (-not $Aws) { Finish "failed" "AWS CLI not found (user-data installs it; wait for C:\setup-complete.json)" }
$Git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $Git) {
    foreach ($c in @("C:\Program Files\Git\cmd\git.exe", "C:\Program Files\Git\bin\git.exe")) { if (Test-Path $c) { $Git = $c; break } }
}
if (-not $Git) {
    Log "git not found; installing Git for Windows via winget/direct download"
    $gitSetup = Join-Path $env:TEMP "GitSetup.exe"
    Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe" -OutFile $gitSetup
    Start-Process -FilePath $gitSetup -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /COMPONENTS=gitlfs" -Wait
    $Git = "C:\Program Files\Git\cmd\git.exe"
}
Log "aws: $Aws"
Log "git: $Git ($(& $Git --version))"

# ---------------------------------------------------------------------------------
Step "Data volume"
# Restored volumes can come up offline / read-only on a new instance.
Get-Disk | Where-Object { $_.OperationalStatus -eq "Offline" } | ForEach-Object {
    Log "Bringing disk $($_.Number) online"
    Set-Disk -Number $_.Number -IsOffline $false
    Set-Disk -Number $_.Number -IsReadOnly $false
}
Start-Sleep -Seconds 3
$Volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" } | Sort-Object DriveLetter
$Volumes | ForEach-Object { Log ("  {0}: {1,8:N0} GB free of {2,8:N0} GB  {3}" -f $_.DriveLetter, ($_.SizeRemaining/1GB), ($_.Size/1GB), $_.FileSystemLabel) }

# Locate RunUAT.bat of the UE 5.6 source build (prefer non-C: drives, shallow search).
$UERoot = $null
$Candidates = @()
foreach ($v in $Volumes) {
    $root = "$($v.DriveLetter):\"
    $depthDirs = @($root) + (Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($d in $depthDirs) {
        $uat = Join-Path $d "Engine\Build\BatchFiles\RunUAT.bat"
        if (Test-Path $uat) { $Candidates += $d }
    }
}
$Candidates = $Candidates | Where-Object { -not $_.StartsWith("C:\", [System.StringComparison]::OrdinalIgnoreCase) } + ($Candidates | Where-Object { $_.StartsWith("C:\", [System.StringComparison]::OrdinalIgnoreCase) })
foreach ($c in $Candidates) {
    $ver = Join-Path $c "Engine\Build\Build.version"
    if (Test-Path $ver) {
        $j = Get-Content $ver | ConvertFrom-Json
        Log "  engine candidate: $c  (v$($j.MajorVersion).$($j.MinorVersion).$($j.PatchVersion), branch $($j.BranchName))"
        if (-not $UERoot -and $j.MajorVersion -eq 5 -and $j.MinorVersion -eq 6) { $UERoot = $c }
    }
}
if (-not $UERoot) { Finish "failed" "No UE 5.6 engine root with Engine\Build\BatchFiles\RunUAT.bat found on any volume" }
Log "UE root: $UERoot"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
if (-not (Test-Path $EditorCmd)) { Log "WARNING: UnrealEditor-Cmd.exe not present; -build will have to compile the editor first (long)" }
if (-not $ProjectsRoot) { $ProjectsRoot = Join-Path ($UERoot.Substring(0, 3)) "UE_5_6_Projects" }
New-Item -ItemType Directory -Force -Path $ProjectsRoot | Out-Null

# ---------------------------------------------------------------------------------
Step "Linux cross toolchain"
# UE 5.6 ships against v25 (clang 18.1.0, rockylinux8).
$ToolchainName = "v25_clang-18.1.0-rockylinux8"
$ToolchainRoot = $env:LINUX_MULTIARCH_ROOT
if (-not $ToolchainRoot -or -not (Test-Path (Join-Path $ToolchainRoot "x86_64-unknown-linux-gnu\bin\clang++.exe"))) {
    $guess = "C:\UnrealToolchains\$ToolchainName"
    if (Test-Path (Join-Path $guess "x86_64-unknown-linux-gnu\bin\clang++.exe")) {
        $ToolchainRoot = $guess
    } else {
        Log "Toolchain $ToolchainName not found; installing from Epic CDN (~1.5 GB)"
        $tcSetup = Join-Path $env:TEMP "$ToolchainName.exe"
        Invoke-WebRequest -Uri "https://cdn.unrealengine.com/CrossToolchain_Linux/$ToolchainName.exe" -OutFile $tcSetup
        Start-Process -FilePath $tcSetup -ArgumentList "/S" -Wait
        $ToolchainRoot = $guess
        if (-not (Test-Path (Join-Path $ToolchainRoot "x86_64-unknown-linux-gnu\bin\clang++.exe"))) { Finish "failed" "Toolchain install did not produce $ToolchainRoot" }
    }
    [Environment]::SetEnvironmentVariable("LINUX_MULTIARCH_ROOT", $ToolchainRoot, "Machine")
    $env:LINUX_MULTIARCH_ROOT = $ToolchainRoot
}
Log "LINUX_MULTIARCH_ROOT=$ToolchainRoot"

# ---------------------------------------------------------------------------------
Step "Project checkout ($Ref)"
$ProjectDir = Join-Path $ProjectsRoot $ProjectName
if (Test-Path (Join-Path $ProjectDir ".git")) {
    & $Git -C $ProjectDir fetch --all --tags --prune 2>&1 | Out-File $LogFile -Append
} else {
    & $Git clone --quiet $RepoUrl $ProjectDir 2>&1 | Out-File $LogFile -Append
}
& $Git -C $ProjectDir checkout --quiet --force $Ref 2>&1 | Out-File $LogFile -Append
# If Ref is a branch, make sure it is at the remote tip.
$isBranch = (& $Git -C $ProjectDir show-ref --verify --quiet "refs/remotes/origin/$Ref"; $LASTEXITCODE -eq 0)
if ($isBranch) { & $Git -C $ProjectDir reset --quiet --hard "origin/$Ref" 2>&1 | Out-File $LogFile -Append }
$Sha = (& $Git -C $ProjectDir rev-parse --short HEAD).Trim()
$Summary.Ref = $Ref; $Summary.Commit = $Sha
Log "checked out $Ref @ $Sha in $ProjectDir"
$UProject = Join-Path $ProjectDir "$ProjectName.uproject"
if (-not (Test-Path $UProject)) { Finish "failed" "$UProject not found" }

# ---------------------------------------------------------------------------------
$RunUAT  = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
$Archive = Join-Path $ProjectDir "Saved\StagedBuilds"
function Invoke-UAT([string]$Platform) {
    $args = @(
        "BuildCookRun",
        "-project=`"$UProject`"",
        "-platform=$Platform", "-server", "-noclient", "-serverconfig=Development",
        "-build", "-nop4", "-utf8output", "-unattended", "-nullrhi"
    )
    if (-not $SkipCook) { $args += @("-cook", "-stage", "-pak", "-archive", "-archivedirectory=`"$Archive`"") }
    Log "RunUAT $($args -join ' ')"
    $uatLog = Join-Path $WorkDir "uat-$Platform-$Stamp.log"
    $p = Start-Process -FilePath $RunUAT -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $uatLog -RedirectStandardError "$uatLog.err"
    Get-Content $uatLog -Tail 15 | ForEach-Object { Log "  uat| $_" }
    if ($p.ExitCode -ne 0) {
        Get-Content $uatLog | Select-String -Pattern "error", "Error:", "ERROR" | Select-Object -Last 20 | ForEach-Object { Log "  uat-err| $($_.Line)" }
        if ($S3Bucket) { & $Aws s3 cp $uatLog "s3://$S3Bucket/builds/logs/" --only-show-errors | Out-Null }
        Finish "failed" "RunUAT ($Platform) exit code $($p.ExitCode); see $uatLog"
    }
    if ($S3Bucket) { & $Aws s3 cp $uatLog "s3://$S3Bucket/builds/logs/" --only-show-errors | Out-Null }
}

Step "BuildCookRun Linux server"
$t0 = Get-Date
Invoke-UAT "Linux"
Log ("Linux server done in {0:N1} min" -f ((Get-Date) - $t0).TotalMinutes)

if ($AlsoWindows) {
    Step "BuildCookRun Win64 server"
    $t0 = Get-Date
    Invoke-UAT "Win64"
    Log ("Win64 server done in {0:N1} min" -f ((Get-Date) - $t0).TotalMinutes)
}

if ($SkipCook) { Finish "ok" "compile only (-SkipCook); nothing staged" }

# ---------------------------------------------------------------------------------
Step "Package and upload"
$Staged = Join-Path $Archive "LinuxServer"
if (-not (Test-Path (Join-Path $Staged "$($ProjectName)Server.sh"))) { Finish "failed" "Staged build missing $Staged\$($ProjectName)Server.sh" }
$ZipName = "$ProjectName-LinuxServer-$Sha-$Stamp.zip"
$ZipPath = Join-Path $WorkDir $ZipName
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
# Compress-Archive is slow and caps at 2 GB; use tar (ships with Windows Server 2019+).
Push-Location $Archive
& tar.exe -a -cf $ZipPath LinuxServer
Pop-Location
$SizeGB = (Get-Item $ZipPath).Length / 1GB
Log ("{0}  ({1:N2} GB)" -f $ZipName, $SizeGB)
$Summary.Artifact = $ZipName
$Summary.ArtifactSizeGB = [math]::Round($SizeGB, 2)

if ($AlsoWindows) {
    $WinZip = Join-Path $WorkDir "$ProjectName-WindowsServer-$Sha-$Stamp.zip"
    Push-Location $Archive; & tar.exe -a -cf $WinZip WindowsServer; Pop-Location
    $Summary.WindowsArtifact = Split-Path $WinZip -Leaf
}

if ($S3Bucket) {
    & $Aws s3 cp $ZipPath "s3://$S3Bucket/builds/$ZipName" --only-show-errors
    if ($LASTEXITCODE -ne 0) { Finish "failed" "S3 upload failed" }
    $Summary.S3 = "s3://$S3Bucket/builds/$ZipName"
    if ($AlsoWindows) { & $Aws s3 cp $WinZip "s3://$S3Bucket/builds/" --only-show-errors; $Summary.WindowsS3 = "s3://$S3Bucket/builds/$($Summary.WindowsArtifact)" }
    Log "uploaded to $($Summary.S3)"
}

Finish "ok" "LinuxServer staged and uploaded"
