# Custom AMI Builder for Unreal Engine 5 Development

This directory contains scripts and tools for building custom Amazon Machine Images (AMIs) with Visual Studio Community 2022 and Nice DCV pre-installed for Unreal Engine 5 development.

## Overview

Building a custom AMI with all the necessary development tools pre-installed provides several benefits:

- **Faster Instance Launch**: No need to wait for software installation during instance startup
- **Consistency**: All team members get identical development environments
- **Reliability**: Eliminates installation failures during instance launch
- **Cost Efficiency**: Reduces the time instances need to be running for setup

## What's Included in the Custom AMI

The custom AMI contains:

### Core Operating System
- Windows Server 2022 (latest)
- Windows Subsystem for Linux (WSL)
- Virtual Machine Platform

### Development Tools
- **Visual Studio Community 2022**
  - C++ development tools
  - Native desktop development workload
  - Managed desktop development workload
- **Build Tools**
  - CMake
  - Ninja
  - Make
  - Git
  - Python 3.x
  - 7-Zip

### Visual C++ Redistributables
- Visual C++ Redistributable 2015, 2017, 2019, 2022
- All necessary runtime libraries for Unreal Engine

### Remote Access
- **Nice DCV Server** (latest version)
- **Nice DCV Virtual Display Driver**
- Pre-configured DCV settings for optimal performance

### System Optimization
- Performance power plan enabled
- Hibernation disabled (frees disk space)
- Windows Defender exclusions for development paths
- Optimized for development workloads

## Prerequisites

Before building the custom AMI, ensure you have:

1. **AWS CLI** installed and configured with appropriate permissions
2. **Terraform** installed and your infrastructure deployed
3. **jq** installed for JSON parsing
4. **AWS Permissions** for:
   - EC2 instance creation and management
   - AMI creation and management
   - IAM role usage
   - VPC and security group access

## Quick Start

### 1. Build the Custom AMI

```bash
# Navigate to the AMI builder directory
cd scripts/ami-builder

# Build AMI with default settings
./build-custom-ami.sh

# Build with custom instance type (faster builds)
./build-custom-ami.sh -i c5.4xlarge

# Build with custom AMI name
./build-custom-ami.sh -n my-team-ue5-ami

# Build and keep the instance for inspection
./build-custom-ami.sh -k
```

### 2. Monitor the Build Process

The build process typically takes 2-4 hours depending on the instance type:

```bash
# Check build progress
aws ec2 describe-instances --filters "Name=tag:Purpose,Values=AMI-Builder"

# View instance logs (if kept)
aws ec2 get-password-data --instance-id <instance-id>
```

### 3. Use the Custom AMI

Once the AMI is created, update your Terraform configuration:

```hcl
# In your compute module
data "aws_ami" "custom_ue5" {
  most_recent = true
  owners      = ["self"]
  
  filter {
    name   = "image-id"
    values = ["ami-xxxxxxxxx"]  # Your custom AMI ID
  }
}

# Use the custom AMI
resource "aws_instance" "ue5_dev" {
  ami           = data.aws_ami.custom_ue5.id
  instance_type = "c5.2xlarge"
  # ... other configuration
}
```

## Scripts Overview

### `build-custom-ami.sh`

The main script that orchestrates the entire AMI creation process:

- Creates a temporary EC2 instance
- Waits for Windows to be ready
- Monitors software installation
- Creates AMI from the configured instance
- Cleans up temporary resources

**Options:**
- `-e, --environment`: Environment to use (dev/staging/prod)
- `-i, --instance-type`: EC2 instance type for building
- `-n, --ami-name`: Custom name for the AMI
- `-d, --description`: Description for the AMI
- `-t, --timeout`: Build timeout in hours
- `-k, --keep-instance`: Keep the build instance after AMI creation

### `cleanup-ami-builder.sh`

Cleans up AMI builder resources and artifacts:

- Terminates AMI builder instances
- Deregisters custom AMIs
- Removes temporary files

**Options:**
- `-a, --all`: Clean up everything
- `-i, --instances`: Clean up only instances
- `-m, --amis`: Clean up only AMIs
- `-f, --force`: Force cleanup without confirmation
- `-d, --dry-run`: Show what would be cleaned up

## Build Process Details

### Phase 1: Instance Creation
1. Launches Windows Server 2022 instance
2. Uses your existing VPC, subnet, and security groups
3. Applies appropriate IAM role for permissions
4. Tags instance for easy identification

### Phase 2: Software Installation
1. **Chocolatey Package Manager**: Installs package manager for Windows
2. **Visual Studio 2022**: Downloads and installs with required workloads
3. **Development Tools**: Git, Python, CMake, and other build tools
4. **Nice DCV**: Server and virtual display driver installation
5. **System Optimization**: Performance tuning and Windows Defender configuration

### Phase 3: AMI Creation
1. Stops the instance (required for AMI creation)
2. Creates AMI with descriptive name and tags
3. Waits for AMI to become available
4. Cleans up temporary instance (unless `-k` flag used)

## Cost Considerations

Building custom AMIs incurs costs:

- **EC2 Instance**: Running time during build (2-4 hours)
- **AMI Storage**: EBS snapshot storage costs
- **Data Transfer**: Software downloads during installation

**Estimated Costs (us-east-1):**
- c5.2xlarge: ~$2-4 per build
- c5.4xlarge: ~$4-8 per build
- AMI Storage: ~$0.05 per GB per month

## Best Practices

### 1. Instance Type Selection
- **c5.2xlarge**: Good balance of cost and speed
- **c5.4xlarge**: Faster builds, higher cost
- **c5.9xlarge**: Fastest builds, highest cost

### 2. AMI Management
- Use descriptive names and tags
- Document AMI contents and versions
- Regularly update AMIs with latest software versions
- Clean up old AMIs to reduce storage costs

### 3. Security
- AMIs inherit security from your VPC configuration
- Consider sharing AMIs only within your organization
- Regularly update base Windows Server images

## Troubleshooting

### Common Issues

1. **Build Timeout**
   ```bash
   # Increase timeout
   ./build-custom-ami.sh -t 6
   ```

2. **Instance Launch Failure**
   - Check VPC and subnet configuration
   - Verify security group rules
   - Ensure IAM role has necessary permissions

3. **Software Installation Issues**
   - Check instance logs in AWS Console
   - Verify internet connectivity
   - Check Windows Event Viewer for errors

### Debug Mode

```bash
# Keep instance for debugging
./build-custom-ami.sh -k

# Connect to instance for inspection
aws ec2 get-password-data --instance-id <instance-id>
```

### Log Files

The build process creates detailed logs:
- `C:\logs\ami-builder-setup.log`: Main setup log
- `C:\logs\dcv-server-install.log`: DCV installation log
- `C:\logs\dcv-display-install.log`: Display driver log

## Integration with Existing Infrastructure

The AMI builder integrates seamlessly with your existing Terraform infrastructure:

- Uses existing VPC, subnets, and security groups
- Leverages existing IAM roles and policies
- Follows your tagging and naming conventions
- Integrates with your monitoring and logging setup

## Next Steps

After building your custom AMI:

1. **Test the AMI**: Launch a test instance to verify all tools work
2. **Update Terraform**: Modify your compute module to use the custom AMI
3. **Team Sharing**: Share the AMI with your development team
4. **Automation**: Consider automating AMI updates with CI/CD pipelines
5. **Documentation**: Document the AMI contents and usage for your team

## Support

For issues or questions:

1. Check the logs in the AWS Console
2. Review the troubleshooting section above
3. Check your AWS permissions and configuration
4. Verify your Terraform infrastructure is properly deployed

## Security Notes

- Custom AMIs inherit security from your VPC configuration
- Consider using AWS Systems Manager for secure access instead of RDP
- Regularly update base images and software packages
- Monitor AMI usage and access patterns
