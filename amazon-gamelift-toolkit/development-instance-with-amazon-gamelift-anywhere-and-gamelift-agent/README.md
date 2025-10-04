# Development Instance with Amazon GameLift Anywhere and GameLift Agent

This directory contains scripts and configuration files for setting up a development instance with Amazon GameLift Anywhere and the GameLift Agent. This setup allows you to run game servers on your own infrastructure for development and testing purposes.

## Overview

This solution creates a complete development environment that includes:

- An EC2 instance running Amazon Linux 2023
- Amazon GameLift Agent for managing game sessions
- A sample game server binary
- CloudWatch logging configuration
- IAM roles and policies for proper permissions
- Security groups for network access

## Prerequisites

Before running these scripts, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Java** installed (required for the GameLift Agent)
3. **Maven** installed (for building the GameLift Agent)
4. **Sample game server binary** built and available as `AmazonGameLiftSampleServerBinary.zip` in the parent directory
5. **AWS permissions** to create EC2 instances, IAM roles, GameLift resources, and S3 buckets

## Files Description

### `deploy_dev_instance.sh`

This is the main deployment script that automates the entire setup process. It performs the following operations:

1. **Validation**: Checks that required tools (Java, Maven) are installed and validates the environment
2. **S3 Setup**: Creates an S3 bucket and uploads the GameLift Agent and game server binary
3. **GameLift Resources**: Creates GameLift Anywhere location and fleet
4. **EC2 Infrastructure**: Creates IAM roles, security groups, and EC2 instance
5. **Deployment**: Uses AWS Systems Manager to deploy and configure the game server

### `dev-game-server-setup-and-deployment.json`

This JSON file contains the SSM (Systems Manager) command configuration that will be executed on the EC2 instance. It includes commands to:

- Install Java
- Download and setup the GameLift Agent
- Download and extract the game server binary
- Configure CloudWatch logging
- Start the GameLift Agent with appropriate parameters

## Usage

1. **Configure the script**: Edit `deploy_dev_instance.sh` and update the `BUCKET_NAME` variable with a globally unique name:
   ```bash
   BUCKET_NAME="your-unique-bucket-name"
   ```

2. **Build the sample game server**: Ensure you have built the sample game server and placed it as `AmazonGameLiftSampleServerBinary.zip` in the parent directory.

3. **Run the deployment script**:
   ```bash
   ./deploy_dev_instance.sh
   ```

4. **Monitor the deployment**: The script will output progress information and should complete in a few minutes.

5. **Verify the setup**: Once complete, you should be able to start game sessions through the GameLift console or API.

## Configuration Parameters

Before running the deployment, you may need to modify these parameters in `dev-game-server-setup-and-deployment.json`:

- `FLEET_ID`: Will be automatically replaced by the deployment script
- `S3_BUCKET`: Will be automatically replaced by the deployment script
- `GAME_EXECUTABLE`: The name of your game server executable (default: "GameLiftSampleServer")
- `COMPUTE_TYPE`: Set to "ANYWHERE" for GameLift Anywhere

## Architecture

The deployment creates the following AWS resources:

- **EC2 Instance**: Amazon Linux 2023 (m6i.large) with public IP
- **IAM Role**: `DevelopmentGameServerInstanceRole` with GameLift, S3, SSM, and CloudWatch permissions
- **Security Group**: Allows inbound traffic on port 1935 (game server port)
- **GameLift Fleet**: Anywhere fleet configured for custom location
- **GameLift Location**: Custom location for the development environment
- **S3 Bucket**: Stores the GameLift Agent and game server binary

## Monitoring and Logging

The setup includes CloudWatch Agent configuration for centralized logging. Game server logs will be available in CloudWatch Logs under the appropriate log group.

## Security Considerations

- The EC2 instance is launched in the default VPC with a public IP
- Security group allows inbound traffic on port 1935 from anywhere (0.0.0.0/0)
- IAM role follows the principle of least privilege for GameLift operations
- Consider restricting the security group to specific IP ranges for production use

## Troubleshooting

1. **Instance not starting**: Check IAM permissions and ensure the instance profile is properly attached
2. **GameLift Agent not connecting**: Verify the fleet ID and location name are correct
3. **Game server not responding**: Check CloudWatch logs and ensure port 1935 is accessible
4. **S3 access denied**: Ensure the IAM role has S3 read permissions

## Cleanup

To clean up the resources created by this script:

1. Terminate the EC2 instance
2. Delete the S3 bucket and its contents
3. Delete the GameLift fleet and location
4. Remove the IAM role and instance profile
5. Delete the security group

## Cost Considerations

- EC2 instance costs will be incurred while the instance is running
- GameLift Anywhere has a cost of $0.20 per hour for the fleet (as configured)
- S3 storage costs for the bucket contents
- CloudWatch logging costs based on log volume

## References

- [Amazon GameLift Anywhere Documentation](https://docs.aws.amazon.com/gamelift/latest/developerguide/gamelift-anywhere.html)
- [GameLift Agent Documentation](https://docs.aws.amazon.com/gamelift/latest/developerguide/gamelift-anywhere-agent.html)
- [AWS Systems Manager Documentation](https://docs.aws.amazon.com/systems-manager/)

## License and Attribution

This code is based on the [Amazon GameLift Toolkit](https://github.com/amazon-gamelift/amazon-gamelift-toolkit) repository, specifically the `development-instance-with-amazon-gamelift-anywhere-and-gamelift-agent` directory.

**Original Authors**: Amazon GameLift Team  
**Source Repository**: https://github.com/amazon-gamelift/amazon-gamelift-toolkit  
**License**: Apache-2.0

The original repository contains sample scripts and code snippets for working with Amazon GameLift Servers and is intended for guidance purposes. Always validate your implementation for security and operational readiness.

## Support

For issues related to this development setup:

1. Check the [Amazon GameLift documentation](https://docs.aws.amazon.com/gamelift/)
2. Review the [original toolkit repository](https://github.com/amazon-gamelift/amazon-gamelift-toolkit)
3. Consult AWS support for GameLift-specific issues
