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

# Create completion marker with SSM status
$marker = @{
    Timestamp = Get-Date
    Status = "Ready"
    Instance = $env:COMPUTERNAME
    SSMAgent = $ssmStatus.ToString()
}
$marker | ConvertTo-Json | Out-File -FilePath "C:\setup-complete.json"

Write-Output "Setup completed at $(Get-Date)"
</powershell>