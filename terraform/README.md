# Unreal Engine 5 Compilation Infrastructure on AWS

This Terraform configuration deploys a complete infrastructure for compiling Unreal Engine 5 on AWS, following the best practices from the [AWS AppMod Blueprints](https://github.com/aws-samples/appmod-blueprints) repository.

## Overview

This infrastructure provides:
- **Windows Server 2022 EC2 instance** optimized for Unreal Engine 5 compilation
- **Automated setup** with PowerShell user data script
- **Secure networking** with VPC, subnets, and security groups
- **IAM roles and policies** for AWS service access
- **EBS volumes** for source code and build artifacts
- **Cost optimization** options with spot instances

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Infrastructure                       │
├─────────────────────────────────────────────────────────────┤
│  VPC (10.0.0.0/16)                                          │
│  ├── Public Subnet (10.0.0.0/24)                            │
│  │   └── EC2 Instance (Windows Server 2022)                 │
│  │       ├── Root Volume (100GB GP3)                        │
│  │       ├── Data Volume (500GB GP3)                        │
│  │       └── IAM Role (CloudWatch, S3 access)               │
│  ├── Private Subnet (10.0.10.0/24)                          │
│  ├── Internet Gateway                                       │
│  ├── NAT Gateway (optional)                                 │
│  └── Security Groups (RDP, WinRM, HTTP/HTTPS)               │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### AWS Requirements
- AWS CLI configured with appropriate permissions
- Terraform >= 1.0 installed
- AWS account with permissions for:
  - EC2 (instances, volumes, security groups)
  - VPC (VPC, subnets, route tables, internet gateway)
  - IAM (roles, policies, instance profiles)
  - CloudWatch Logs
  - S3 (optional, for build artifacts)

### Epic Games Requirements
- **GitHub account linked to Epic Games** for Unreal Engine repository access
- Epic Games account with Unreal Engine access

### Local Requirements
- Terraform CLI
- AWS CLI
- Git

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd UnrealEngine5DedicatedServersWithAWSAndGameLift/terraform

# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit the configuration
nano terraform.tfvars
```

### 2. Configure Variables

Edit `terraform.tfvars` with your specific values:

```hcl
# Essential configurations
project_name = "my-ue5-compilation"
environment  = "dev"
aws_region   = "us-east-1"

# Security - IMPORTANT: Restrict to your IP
allowed_cidr_blocks = ["YOUR_IP_ADDRESS/32"]  # Replace with your IP

# Instance configuration
instance_type = "c5.2xlarge"  # Minimum recommended
key_pair_name = "your-key-pair-name"  # Optional

# Unreal Engine configuration
unreal_engine_version = "5.4"
unreal_engine_branch  = "5.4"
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Connect and Monitor

After deployment, you'll see output with connection details:

```bash
# View outputs
terraform output connection_instructions
```

Connect via RDP using the provided public IP address.

## Configuration Options

### Instance Types

| Instance Type | vCPUs | RAM | Use Case |
|---------------|-------|-----|----------|
| `c5.2xlarge`  | 8     | 16GB| Minimum recommended |
| `c5.4xlarge`  | 16    | 32GB| Better performance |
| `c5.9xlarge`  | 36    | 72GB| High performance |
| `c5.18xlarge` | 72    | 144GB| Maximum performance |

### Build Components

- **Editor**: Full Unreal Engine 5 editor (default: enabled)
- **Server**: Server binaries for dedicated servers (default: enabled)
- **Linux**: Linux server binaries (default: disabled)

### Cost Optimization

- **Spot Instances**: Enable `enable_spot_instance = true` for up to 90% cost savings
- **Instance Scheduling**: Use AWS Instance Scheduler for automatic start/stop
- **Right-sizing**: Monitor usage and adjust instance types accordingly

## Security Best Practices

### Network Security
- Restrict `allowed_cidr_blocks` to your specific IP address
- Use VPN or AWS Direct Connect for secure access
- Consider using AWS Systems Manager Session Manager instead of RDP

### Instance Security
- Enable IMDSv2 (already configured)
- Use encrypted EBS volumes (already configured)
- Implement least-privilege IAM policies
- Regular security updates

### Access Control
- Use AWS Secrets Manager for sensitive data
- Implement multi-factor authentication
- Regular access reviews

## Monitoring and Logging

### CloudWatch Integration
The infrastructure includes CloudWatch Logs integration for:
- Application logs
- System logs
- Build process logs

### Log Locations on Instance
- `C:\logs\ue5-setup.log` - Setup script logs
- `C:\logs\setup-completion.txt` - Build completion summary
- `C:\logs\ue5-*-build-error.log` - Build error logs

## Troubleshooting

### Common Issues

#### 1. Unreal Engine Repository Access
```
Error: Failed to clone Unreal Engine repository
```
**Solution**: Ensure your GitHub account is linked to Epic Games and you have access to the UnrealEngine repository.

#### 2. Build Timeout
```
Error: Build timeout reached
```
**Solution**: 
- Increase `build_timeout_hours` in terraform.tfvars
- Use a larger instance type
- Check network connectivity

#### 3. Insufficient Disk Space
```
Error: Not enough disk space
```
**Solution**: 
- Increase `root_volume_size` in terraform.tfvars
- The additional 500GB data volume is automatically attached

#### 4. RDP Connection Issues
```
Error: Cannot connect via RDP
```
**Solution**:
- Verify security group allows RDP (port 3389) from your IP
- Check if the instance is running
- Verify the user data script completed successfully

### Debugging Steps

1. **Check Instance Status**:
   ```bash
   aws ec2 describe-instances --instance-ids <instance-id>
   ```

2. **View User Data Logs**:
   Connect to the instance and check:
   ```
   C:\logs\ue5-setup.log
   ```

3. **Check CloudWatch Logs**:
   ```bash
   aws logs describe-log-groups --log-group-name-prefix "/aws/ec2"
   ```

## Cost Estimation

### Monthly Costs (us-east-1)

| Instance Type | On-Demand | Spot (estimated) |
|---------------|-----------|------------------|
| c5.2xlarge    | ~$300     | ~$60-90          |
| c5.4xlarge    | ~$600     | ~$120-180        |
| c5.9xlarge    | ~$1,350   | ~$270-405        |

**Additional costs**:
- EBS volumes: ~$50-100/month
- Data transfer: Varies
- NAT Gateway: ~$45/month (if enabled)

## Cleanup

To avoid unnecessary costs, destroy the infrastructure when not in use:

```bash
# Destroy the infrastructure
terraform destroy

# Confirm destruction
yes
```

## Contributing

This infrastructure follows the patterns and best practices from the [AWS AppMod Blueprints](https://github.com/aws-samples/appmod-blueprints) repository. Contributions are welcome!

### Development Guidelines
- Use dynamic variables instead of hardcoded values
- Follow AWS security best practices
- Include proper documentation
- Test in a development environment first

## References

- [AWS AppMod Blueprints](https://github.com/aws-samples/appmod-blueprints)
- [Unreal Engine 5 Documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/setting-up-your-development-environment-for-cplusplus-in-unreal-engine)
- [Unreal Engine GitHub Repository](https://github.com/EpicGames/UnrealEngine)
- [AWS EC2 User Guide](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## License

This project is licensed under the MIT-0 License, following the same license as the AWS AppMod Blueprints repository. 