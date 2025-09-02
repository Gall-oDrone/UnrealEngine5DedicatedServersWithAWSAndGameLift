<powershell>
# Minimal Windows Setup Script (< 1KB)
# Only sets admin password and basic config

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

# Create completion marker
$marker = @{
    Timestamp = Get-Date
    Status = "Ready"
    Instance = $env:COMPUTERNAME
}
$marker | ConvertTo-Json | Out-File -FilePath "C:\setup-complete.json"

Write-Output "Setup completed at $(Get-Date)"
</powershell>