<#
.SYNOPSIS
  Builds, cooks and stages the FrontendUI Linux dedicated server on the UE 5.6 build box,
  then uploads the staged build to S3. Runs unattended under SSM (AWS-RunPowerShellScript)
  or interactively in an elevated PowerShell. Targets Windows PowerShell 5.1.

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

.PARAMETER RepoUrl       Git URL of the game project.
.PARAMETER Ref           Branch or tag to build (default master).
.PARAMETER ProjectName   .uproject name without extension (default FrontendUI).
.PARAMETER S3Bucket      Artifacts bucket. Empty = skip upload.
.PARAMETER ProjectsRoot  Where to clone (default <engine drive>:\UE_5_6_Projects).
.PARAMETER Platforms     Server platforms to build, in order (default Linux). e.g. -Platforms Linux,Win64; None = no server
.PARAMETER AlsoWindows   Shorthand for -Platforms Linux,Win64.
.PARAMETER SkipCook      Build the server binary only (quick compile check).
.PARAMETER WindowsClient Also build, cook and stage the Win64 *client* in -ClientConfig (default Shipping)
                         and upload <Project>-WindowsClient-<Config>-<sha>-<stamp>.zip. A Shipping client
                         cannot take -ini: overrides, so the deployment values below are appended to the
                         checkout's Config\DefaultGame.ini / DefaultEngine.ini for the build and reverted after.
.PARAMETER ClientConfig  Client configuration (default Shipping).
.PARAMETER GameLiftEndpoint, GameLiftAlias, GameLiftLocation, GameLiftQueue, GameLiftRegion
                         Values baked into the client's FrontendGameLiftSettings (ApiEndpointUrl, AliasId, ...).
.PARAMETER EosArtifactsParameter
                         SSM parameter (SecureString) holding the EOS "+Artifacts=(...)" line for DefaultEngine.ini
                         (default /frontendui/eos/artifacts). Missing = the client ships on the Null subsystem
                         with the plain GameLift backend (a proxy in auth_mode=eos will reject it).
#>
[CmdletBinding()]
param(
    [string]$RepoUrl      = "https://github.com/Gall-oDrone/Tutorial-FrontendUI-Experience-In-UnrealEngine-5-Using-C-And-Common-UI.git",
    [string]$Ref          = "master",
    [string]$ProjectName  = "FrontendUI",
    [string]$S3Bucket     = "ue5-artifacts-326105557351-us-east-1",
    [string]$ProjectsRoot = "",
    [string[]]$Platforms  = @("Linux"),
    [switch]$AlsoWindows,
    [switch]$SkipCook,
    [switch]$WindowsClient,
    [string]$ClientConfig = "Shipping",
    [string]$GameLiftEndpoint = "",
    [string]$GameLiftAlias = "",
    [string]$GameLiftLocation = "",
    [string]$GameLiftQueue = "",
    [string]$GameLiftRegion = "us-east-1",
    [string]$EosArtifactsParameter = "/frontendui/eos/artifacts"
)
if ($AlsoWindows -and ($Platforms -notcontains "Win64")) { $Platforms += "Win64" }
# -Platforms None: no server at all (e.g. -WindowsClient on a box that already built the servers).
if ($Platforms.Count -eq 1 -and $Platforms[0] -eq "None") { $Platforms = @() }

# Native tools (git, aws, tar) write progress to stderr. Under 'Stop' PowerShell 5.1
# turns the first such line into a terminating error, so run with 'Continue' and check
# exit codes explicitly through Invoke-Native.
$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"
$Stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$WorkDir = "C:\ue5-build"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$LogFile = Join-Path $WorkDir "build-$Stamp.log"
$Summary = [ordered]@{ Started = (Get-Date).ToString("o"); Status = "running"; Steps = @() }
$Aws = $null

function Log([string]$Msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Msg
    Add-Content -Path $LogFile -Value $line
    Write-Output $line
}
function Step([string]$Name) { $script:Summary.Steps += $Name; Log "== $Name" }

# Runs a native executable, appends its combined output to the log, returns the exit code.
function Invoke-Native {
    param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments = @(), [switch]$Quiet)
    $output = & $Exe @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($output) {
        $text = ($output | ForEach-Object { "$_" }) -join "`r`n"
        Add-Content -Path $LogFile -Value $text
        if (-not $Quiet) { $output | Select-Object -Last 5 | ForEach-Object { Log "  | $_" } }
    }
    return $code
}
function Require-Native([string]$Exe, [string[]]$Arguments, [string]$What) {
    $code = Invoke-Native -Exe $Exe -Arguments $Arguments
    if ($code -ne 0) { Finish "failed" "$What failed (exit $code)" }
}
function Upload([string]$Path, [string]$Key) {
    if (-not $S3Bucket -or -not $script:Aws) { return }
    [void](Invoke-Native -Exe $script:Aws -Arguments @("s3", "cp", $Path, "s3://$S3Bucket/$Key", "--only-show-errors") -Quiet)
}
function Finish([string]$Status, [string]$Message = "") {
    $Summary.Status   = $Status
    $Summary.Message  = $Message
    $Summary.Finished = (Get-Date).ToString("o")
    $Summary.Log      = $LogFile
    $Summary | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $WorkDir "last-build.json") -Encoding utf8
    Log "RESULT: $Status $Message"
    Upload $LogFile "builds/logs/$(Split-Path $LogFile -Leaf)"
    if ($Status -ne "ok") { exit 1 }
    exit 0
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
    Log "git not found; installing Git for Windows"
    $gitSetup = Join-Path $env:TEMP "GitSetup.exe"
    Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe" -OutFile $gitSetup
    Start-Process -FilePath $gitSetup -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /COMPONENTS=gitlfs" -Wait
    $Git = "C:\Program Files\Git\cmd\git.exe"
}
Log "aws: $Aws"
Log "git: $Git"

# ---------------------------------------------------------------------------------
Step "Data volume"
Get-Disk | Where-Object { $_.OperationalStatus -eq "Offline" } | ForEach-Object {
    Log "Bringing disk $($_.Number) online"
    Set-Disk -Number $_.Number -IsOffline $false
    Set-Disk -Number $_.Number -IsReadOnly $false
}
Start-Sleep -Seconds 3
$Volumes = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" } | Sort-Object DriveLetter)
foreach ($v in $Volumes) { Log ("  {0}: {1,8:N0} GB free of {2,8:N0} GB  {3}" -f $v.DriveLetter, ($v.SizeRemaining/1GB), ($v.Size/1GB), $v.FileSystemLabel) }

# Locate RunUAT.bat of the UE 5.6 source build: each fixed volume, one directory deep.
$Candidates = @()
foreach ($v in $Volumes) {
    $root = "$($v.DriveLetter):\"
    $dirs = @($root)
    $dirs += @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($d in $dirs) {
        if (Test-Path (Join-Path $d "Engine\Build\BatchFiles\RunUAT.bat")) { $Candidates += $d }
    }
}
# Prefer engines that are not on the OS disk.
$OnData = @($Candidates | Where-Object { -not $_.StartsWith("C:\", [System.StringComparison]::OrdinalIgnoreCase) })
$OnOs   = @($Candidates | Where-Object { $_.StartsWith("C:\", [System.StringComparison]::OrdinalIgnoreCase) })
$Candidates = $OnData + $OnOs

$UERoot = $null
foreach ($c in $Candidates) {
    $ver = Join-Path $c "Engine\Build\Build.version"
    if (-not (Test-Path $ver)) { continue }
    $j = Get-Content $ver -Raw | ConvertFrom-Json
    Log "  engine candidate: $c  (v$($j.MajorVersion).$($j.MinorVersion).$($j.PatchVersion), branch $($j.BranchName))"
    if (-not $UERoot -and $j.MajorVersion -eq 5 -and $j.MinorVersion -eq 6) { $UERoot = $c }
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
$ToolchainRoot = [Environment]::GetEnvironmentVariable("LINUX_MULTIARCH_ROOT", "Machine")
if (-not $ToolchainRoot) { $ToolchainRoot = $env:LINUX_MULTIARCH_ROOT }
$ClangRel = "x86_64-unknown-linux-gnu\bin\clang++.exe"
if (-not $ToolchainRoot -or -not (Test-Path (Join-Path $ToolchainRoot $ClangRel))) {
    $guess = "C:\UnrealToolchains\$ToolchainName"
    if (Test-Path (Join-Path $guess $ClangRel)) {
        $ToolchainRoot = $guess
    } else {
        Log "Toolchain $ToolchainName not found; installing from Epic CDN (~1.5 GB)"
        $tcSetup = Join-Path $env:TEMP "$ToolchainName.exe"
        Invoke-WebRequest -Uri "https://cdn.unrealengine.com/CrossToolchain_Linux/$ToolchainName.exe" -OutFile $tcSetup
        Start-Process -FilePath $tcSetup -ArgumentList "/S" -Wait
        $ToolchainRoot = $guess
        if (-not (Test-Path (Join-Path $ToolchainRoot $ClangRel))) { Finish "failed" "Toolchain install did not produce $ToolchainRoot" }
    }
    [Environment]::SetEnvironmentVariable("LINUX_MULTIARCH_ROOT", $ToolchainRoot, "Machine")
}
$env:LINUX_MULTIARCH_ROOT = $ToolchainRoot
Log "LINUX_MULTIARCH_ROOT=$ToolchainRoot"

# ---------------------------------------------------------------------------------
Step "Project checkout ($Ref)"
$ProjectDir = Join-Path $ProjectsRoot $ProjectName
if (Test-Path (Join-Path $ProjectDir ".git")) {
    Require-Native $Git @("-C", $ProjectDir, "fetch", "--all", "--tags", "--prune", "--quiet") "git fetch"
} else {
    Require-Native $Git @("clone", "--quiet", $RepoUrl, $ProjectDir) "git clone"
}
Require-Native $Git @("-C", $ProjectDir, "checkout", "--quiet", "--force", $Ref) "git checkout $Ref"
# If Ref is a branch, make sure it is at the remote tip.
$isBranch = (Invoke-Native -Exe $Git -Arguments @("-C", $ProjectDir, "show-ref", "--verify", "--quiet", "refs/remotes/origin/$Ref") -Quiet) -eq 0
if ($isBranch) { Require-Native $Git @("-C", $ProjectDir, "reset", "--quiet", "--hard", "origin/$Ref") "git reset to origin/$Ref" }
$Sha = ((& $Git -C $ProjectDir rev-parse --short HEAD 2>&1) | Select-Object -First 1).ToString().Trim()
$Summary.Ref = $Ref; $Summary.Commit = $Sha
Log "checked out $Ref @ $Sha in $ProjectDir"
$UProject = Join-Path $ProjectDir "$ProjectName.uproject"
if (-not (Test-Path $UProject)) { Finish "failed" "$UProject not found" }

# ---------------------------------------------------------------------------------
$RunUAT = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
$Staging = Join-Path $ProjectDir "Saved\StagedBuilds"   # where -stage writes <Platform>Server\
function Invoke-UAT([string]$Platform, [string[]]$TargetArgs = @("-server", "-noclient", "-serverconfig=Development"), [string]$Label = "") {
    if (-not $Label) { $Label = $Platform }
    $uatArgs = @(
        "BuildCookRun",
        "-project=`"$UProject`"",
        "-platform=$Platform"
    ) + $TargetArgs + @(
        "-build", "-nop4", "-utf8output", "-unattended", "-nullrhi"
    )
    # -stage alone leaves the result in Saved\StagedBuilds\<Platform>Server; -archive into the
    # same tree makes UAT copy the folder onto itself, so it is deliberately not used.
    if (-not $SkipCook) { $uatArgs += @("-cook", "-stage", "-pak") }
    Log "RunUAT $($uatArgs -join ' ')"
    $uatLog = Join-Path $WorkDir "uat-$Label-$Stamp.log"
    # UAT (re)builds its C# tools with MSBuild, which leaves idle "node reuse" workers alive
    # for ~15 min; `Start-Process -Wait` would wait for those descendants too. Disable node
    # reuse and wait on the UAT process object only.
    $env:MSBUILDDISABLENODEREUSE = "1"
    $p = Start-Process -FilePath $RunUAT -ArgumentList $uatArgs -NoNewWindow -PassThru -RedirectStandardOutput $uatLog -RedirectStandardError "$uatLog.err"
    $null = $p.Handle   # PowerShell quirk: ExitCode stays $null after WaitForExit unless the handle was read first
    $p.WaitForExit()
    $exitCode = if ($null -eq $p.ExitCode) { -1 } else { $p.ExitCode }
    if (Test-Path $uatLog) { Get-Content $uatLog -Tail 12 | ForEach-Object { Log "  uat| $_" } }
    Upload $uatLog "builds/logs/$(Split-Path $uatLog -Leaf)"
    if ($exitCode -ne 0) {
        if (Test-Path $uatLog) {
            Get-Content $uatLog | Select-String -Pattern "error [A-Z]+[0-9]+|Error:|ERROR:|fatal" | Select-Object -Last 20 | ForEach-Object { Log "  uat-err| $($_.Line)" }
        }
        Finish "failed" "RunUAT ($Platform) exit code $exitCode; see $uatLog"
    }
}

foreach ($Platform in $Platforms) {
    Step "BuildCookRun $Platform server"
    $t0 = Get-Date
    Invoke-UAT $Platform
    Log ("{0} server done in {1:N1} min" -f $Platform, ((Get-Date) - $t0).TotalMinutes)
}

if ($SkipCook) { Finish "ok" "compile only (-SkipCook); nothing staged" }

# ---------------------------------------------------------------------------------
Step "Package and upload"
function New-Zip([string]$Folder, [string]$ZipPath) {
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    # Compress-Archive is slow and caps at 2 GB; bsdtar ships with Windows Server 2019+.
    Push-Location $Staging
    try { $code = Invoke-Native -Exe "tar.exe" -Arguments @("-a", "-cf", $ZipPath, $Folder) -Quiet } finally { Pop-Location }
    if ($code -ne 0 -or -not (Test-Path $ZipPath)) { Finish "failed" "tar failed creating $ZipPath (exit $code)" }
    return [math]::Round((Get-Item $ZipPath).Length / 1GB, 2)
}

# Staged folder name and the file that proves it is complete, per platform.
$StagedLayout = @{
    Linux = @{ Folder = "LinuxServer";   Marker = "$($ProjectName)Server.sh" }
    Win64 = @{ Folder = "WindowsServer"; Marker = "$($ProjectName)Server.exe" }
}
$Summary.Artifacts = @()
$Uploaded = 0
foreach ($Platform in $Platforms) {
    $layout = $StagedLayout[$Platform]
    if (-not $layout) { Log "WARNING: no packaging rule for $Platform"; continue }
    $folder = Join-Path $Staging $layout.Folder
    if (-not (Test-Path (Join-Path $folder $layout.Marker))) { Finish "failed" "Staged build missing $folder\$($layout.Marker)" }
    $zipName = "$ProjectName-$($layout.Folder)-$Sha-$Stamp.zip"
    $zipPath = Join-Path $WorkDir $zipName
    $sizeGB  = New-Zip $layout.Folder $zipPath
    Log "$zipName ($sizeGB GB)"
    $entry = [ordered]@{ Platform = $Platform; Zip = $zipName; SizeGB = $sizeGB }
    if ($S3Bucket) {
        $code = Invoke-Native -Exe $Aws -Arguments @("s3", "cp", $zipPath, "s3://$S3Bucket/builds/$zipName", "--only-show-errors")
        if ($code -ne 0) { Finish "failed" "S3 upload of $zipName failed (exit $code)" }
        $entry.S3 = "s3://$S3Bucket/builds/$zipName"
        Log "uploaded $($entry.S3)"
        $Uploaded++
    }
    $Summary.Artifacts += $entry
}

# ---------------------------------------------------------------------------------
if ($WindowsClient) {
    Step "Windows client ($ClientConfig)"
    # A Shipping client reads no -ini: overrides, so what LaunchInstances.bat passes on the
    # command line is appended to the packaged config layer for this build only. The EOS
    # artifact (ids + the Peer2Peer client secret Epic expects inside the game) comes from SSM
    # so it never lands in the repository; without it the client ships on Null + plain GameLift.
    $gameIni   = Join-Path $ProjectDir "Config\DefaultGame.ini"
    $engineIni = Join-Path $ProjectDir "Config\DefaultEngine.ini"
    $artifacts = ""
    if ($EosArtifactsParameter) {
        $raw = & $Aws ssm get-parameter --name $EosArtifactsParameter --with-decryption --query Parameter.Value --output text 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) { $artifacts = (($raw | ForEach-Object { "$_" }) -join "").Trim() }
    }
    if ($artifacts -and -not $artifacts.StartsWith("+Artifacts=")) { $artifacts = "+Artifacts=" + $artifacts }
    if (-not $artifacts) { Log "WARNING: SSM parameter '$EosArtifactsParameter' not found or empty; client will use the Null subsystem and the plain GameLift backend" }

    $backend = if ($artifacts) { "/Script/FrontendMultiplayerOSS.FrontendSessionBackend_GameLiftEOS" } else { "/Script/FrontendMultiplayer.FrontendSessionBackend_GameLift" }
    $gameLines = @("", "; --- appended by build-linux-server.ps1 for the $ClientConfig client build; not committed ---",
        "[/Script/FrontendMultiplayer.FrontendMultiplayerSettings]", "SessionBackendClass=$backend", "",
        "[/Script/FrontendMultiplayer.FrontendGameLiftSettings]", "AwsRegion=$GameLiftRegion")
    if ($GameLiftEndpoint) { $gameLines += "ApiEndpointUrl=$GameLiftEndpoint" }
    if ($GameLiftAlias)    { $gameLines += "AliasId=$GameLiftAlias" }
    if ($GameLiftLocation) { $gameLines += "Location=$GameLiftLocation" }
    if ($GameLiftQueue)    { $gameLines += "GameSessionQueueName=$GameLiftQueue" }
    Add-Content -Path $gameIni -Value ($gameLines -join "`r`n")
    if ($artifacts) {
        $engineLines = @("", "; --- appended by build-linux-server.ps1 for the $ClientConfig client build; not committed ---",
            "[OnlineSubsystem]", "DefaultPlatformService=EOS", "",
            "[/Script/OnlineSubsystemEOS.EOSSettings]", $artifacts)
        Add-Content -Path $engineIni -Value ($engineLines -join "`r`n")
    }
    Log ("client config: backend={0} endpoint={1} alias={2} location={3} queue={4} eos={5}" -f $backend, $GameLiftEndpoint, $GameLiftAlias, $GameLiftLocation, $GameLiftQueue, [bool]$artifacts)

    $t0 = Get-Date
    Invoke-UAT "Win64" @("-clientconfig=$ClientConfig") "Win64Client"
    Log ("Win64 client done in {0:N1} min" -f ((Get-Date) - $t0).TotalMinutes)

    # Put the checkout back before anything else can pick the appended lines up.
    [void](Invoke-Native -Exe $Git -Arguments @("-C", $ProjectDir, "checkout", "--quiet", "--", "Config") -Quiet)

    if (-not $SkipCook) {
        $folder = Join-Path $Staging "Windows"
        if (-not (Test-Path (Join-Path $folder "$ProjectName.exe"))) { Finish "failed" "Staged client missing $folder\$ProjectName.exe" }
        $zipName = "$ProjectName-WindowsClient-$ClientConfig-$Sha-$Stamp.zip"
        $zipPath = Join-Path $WorkDir $zipName
        $sizeGB  = New-Zip "Windows" $zipPath
        Log "$zipName ($sizeGB GB)"
        $entry = [ordered]@{ Platform = "Win64Client-$ClientConfig"; Zip = $zipName; SizeGB = $sizeGB }
        if ($S3Bucket) {
            $code = Invoke-Native -Exe $Aws -Arguments @("s3", "cp", $zipPath, "s3://$S3Bucket/builds/$zipName", "--only-show-errors")
            if ($code -ne 0) { Finish "failed" "S3 upload of $zipName failed (exit $code)" }
            $entry.S3 = "s3://$S3Bucket/builds/$zipName"
            Log "uploaded $($entry.S3)"
            $Uploaded++
        }
        $Summary.Artifacts += $entry
    }
}

Finish "ok" ("staged {0}{1}; uploaded {2} zip(s)" -f ($Platforms -join ","), $(if ($WindowsClient) { ",Win64 client ($ClientConfig)" } else { "" }), $Uploaded)
