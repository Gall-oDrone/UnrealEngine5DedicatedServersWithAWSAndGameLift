<powershell>
# Minimal Windows Setup Script with SSM Agent Verification
# Only sets admin password and ensures SSM Agent is running

# Set Administrator password if provided
$adminPassword = "${admin_password}"
if ($adminPassword -ne "") {
    Write-Output "Setting Administrator password"
    $securePassword = ConvertTo-SecureString -String $adminPassword -AsPlainText -Force
    Set-LocalUser -Name "Administrator" -Password $securePassword
    Write-Output "Administrator password set successfully"
}

# Enable RDP (should be enabled by default, but just in case)
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# IMPORTANT: Ensure SSM Agent is running
Write-Output "Checking SSM Agent status..."
$ssmService = Get-Service -Name "AmazonSSMAgent" -ErrorAction SilentlyContinue

if ($null -eq $ssmService) {
    Write-Output "SSM Agent not found, attempting to install..."
    # Download and install SSM Agent if not present
    $progressPreference = 'SilentlyContinue'
    Invoke-WebRequest `
        -Uri "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe" `
        -OutFile "$env:TEMP\SSMAgentSetup.exe"
    
    Start-Process -FilePath "$env:TEMP\SSMAgentSetup.exe" -ArgumentList "/S" -Wait
    Start-Sleep -Seconds 10
} else {
    Write-Output "SSM Agent found, ensuring it's running..."
}

# Start SSM Agent service
Set-Service -Name "AmazonSSMAgent" -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name "AmazonSSMAgent" -ErrorAction SilentlyContinue

# Wait for SSM Agent to fully initialize
Start-Sleep -Seconds 30

# Verify SSM Agent is running
$ssmStatus = Get-Service -Name "AmazonSSMAgent" | Select-Object -ExpandProperty Status
Write-Output "SSM Agent Status: $ssmStatus"

# Install AWS CLI for Windows
Write-Output "Installing AWS CLI..."
$progressPreference = 'SilentlyContinue'
try {
    # Download AWS CLI installer
    Invoke-WebRequest `
        -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" `
        -OutFile "$env:TEMP\AWSCLIV2.msi"
    
    # Install AWS CLI silently
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$env:TEMP\AWSCLIV2.msi`" /quiet /norestart" -Wait
    
    # Add AWS CLI to PATH for current session
    $env:PATH += ";C:\Program Files\Amazon\AWSCLIV2"
    
    # Verify AWS CLI installation
    $awsVersion = & "C:\Program Files\Amazon\AWSCLIV2\aws.exe" --version 2>$null
    if ($awsVersion) {
        Write-Output "AWS CLI installed successfully: $($awsVersion[0])"
    } else {
        Write-Output "AWS CLI installation may have failed"
    }
} catch {
    Write-Output "Error installing AWS CLI: $($_.Exception.Message)"
}

# Create completion marker with SSM and AWS CLI status
$awsCliStatus = "Not Installed"
try {
    $awsVersion = & "C:\Program Files\Amazon\AWSCLIV2\aws.exe" --version 2>$null
    if ($awsVersion) {
        $awsCliStatus = "Installed"
    }
} catch {
    $awsCliStatus = "Error"
}

$marker = @{
    Timestamp = Get-Date
    Status = "Ready"
    Instance = $env:COMPUTERNAME
    SSMAgent = $ssmStatus.ToString()
    AWSCLI = $awsCliStatus
}
$marker | ConvertTo-Json | Out-File -FilePath "C:\setup-complete.json"

Write-Output "Setup completed at $(Get-Date)"
</powershell>