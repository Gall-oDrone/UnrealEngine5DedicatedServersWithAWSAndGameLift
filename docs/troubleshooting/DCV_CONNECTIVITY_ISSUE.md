# DCV Connectivity Issue - Port 8443 Not Accessible

## Problem Description

After deploying the Unreal Engine 5 infrastructure with Terraform, you're experiencing connectivity issues with NICE DCV:

- **Error**: Timeout when trying to access `https://<PUBLIC_IP>:8443`
- **DCV Viewer**: Connection fails
- **Browser**: Page loads indefinitely or times out

## Root Cause

The issue is that **port 8443 is not included in the security group rules**. The security group only allows:
- Port 3389 (RDP)
- Port 5985-5986 (WinRM) 
- Port 80 (HTTP)
- Port 443 (HTTPS)

But **DCV runs on port 8443**, which is blocked by the security group.

## Solutions

### Option 1: Quick Fix (Immediate)

Run the quick fix script to immediately add the missing port:

```bash
cd UnrealEngine5DedicatedServersWithAWSAndGameLift/scripts/deployment
chmod +x quick-fix-dcv.sh
./quick-fix-dcv.sh
```

This script will:
1. Add port 8443 to your security group
2. Test connectivity
3. Optionally apply Terraform changes to make it permanent

### Option 2: Manual AWS Console Fix

1. Go to AWS EC2 Console
2. Find your instance and note the Security Group
3. Click on the Security Group
4. Add Inbound Rule:
   - Type: Custom TCP
   - Port: 8443
   - Source: Your IP address (or 0.0.0.0/0 for anywhere)
   - Description: NICE DCV access

### Option 3: Terraform Fix (Recommended)

The Terraform configuration has been updated to include port 8443. To apply:

```bash
cd UnrealEngine5DedicatedServersWithAWSAndGameLift/environments/dev
terraform apply
```

This will:
- Add the missing security group rule
- Make the fix permanent in your infrastructure code
- Ensure future deployments include the correct port

## Verification

After applying any fix, verify connectivity:

```bash
# Test if port is open
nc -zv <PUBLIC_IP> 8443

# Or use telnet
telnet <PUBLIC_IP> 8443

# Test in browser
# Open: https://<PUBLIC_IP>:8443
```

## Debugging

If you still have issues after fixing the port, run the debugging script:

```bash
cd UnrealEngine5DedicatedServersWithAWSAndGameLift/scripts/deployment
chmod +x debug-dcv.sh
./debug-dcv.sh
```

This will check:
- Instance status
- Security group rules
- Windows Firewall
- DCV services
- Network connectivity
- Setup logs

## Common Issues

### 1. Setup Still Running
The initial setup takes 20-30 minutes. Check if it's complete:
```bash
# Via SSM (if instance is online)
aws ssm send-command \
  --instance-ids <INSTANCE_ID> \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Test-Path C:\logs\setup-complete.txt"]'
```

### 2. DCV Service Not Started
Check if DCV services are running:
```bash
# Via SSM
aws ssm send-command \
  --instance-ids <INSTANCE_ID> \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Get-Service -Name \"DCV*\""]'
```

### 3. Windows Firewall
Ensure Windows Firewall allows port 8443:
```bash
# Via SSM
aws ssm send-command \
  --instance-ids <INSTANCE_ID> \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Get-NetFirewallRule -DisplayName \"DCV*\""]'
```

## Prevention

To prevent this issue in future deployments:

1. **Always run `terraform plan`** before applying to see what changes will be made
2. **Use the updated Terraform configuration** that includes port 8443
3. **Test connectivity** after deployment using the debugging script
4. **Review security group rules** in the AWS Console to ensure all required ports are open

## Security Considerations

- Port 8443 should only be open to your IP address in production
- Consider using a VPN or bastion host for secure access
- Regularly review and audit security group rules
- Use the principle of least privilege

## Support

If you continue to experience issues:

1. Run the debugging script and share the output
2. Check AWS CloudTrail for any API errors
3. Review CloudWatch logs for the instance
4. Check the DCV setup logs on the instance: `C:\logs\dcv-setup.log`

## Related Files

- `modules/compute/main.tf` - Security group configuration
- `modules/compute/variables.tf` - DCV port variable
- `scripts/deployment/debug-dcv.sh` - Debugging script
- `scripts/deployment/quick-fix-dcv.sh` - Quick fix script
- `modules/compute/templates/user_data.ps1` - DCV setup configuration
