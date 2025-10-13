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
2. **Java** installed (required for the GameLift Agent - Amazon Corretto 23 recommended)
3. **Maven** installed (for building the GameLift Agent)
4. **FPS Template game server** built for Linux and uploaded to S3 at `s3://your-bucket/builders/Linux/Server/FPSTemplate/FPSTemplateServer.zip`
5. **AWS permissions** to create EC2 instances, IAM roles, GameLift resources, and S3 buckets

## Files Description

### `deploy_dev_instance.sh`

This is the main deployment script that automates the entire setup process. It performs the following operations:

1. **Download Game Server**: Downloads `FPSTemplateServer.zip` from your S3 bucket
2. **Validation**: Checks that required tools (Java, Maven) are installed and validates the environment
3. **S3 Setup**: Creates an S3 bucket and uploads the GameLift Agent and game server binary
4. **GameLift Resources**: Creates GameLift Anywhere location and fleet with FPSTemplateServer configuration
5. **EC2 Infrastructure**: Creates IAM roles, security groups, and EC2 instance running Amazon Linux 2023
6. **Deployment**: Uses AWS Systems Manager to deploy and configure the game server
7. **Testing**: Automatically creates a test game session to verify the deployment

### `dev-game-server-setup-and-deployment.json`

This JSON file contains the SSM (Systems Manager) command configuration that will be executed on the EC2 instance. It includes commands to:

- Install Amazon Corretto Java 23 (optimized for Amazon Linux 2023)
- Download and setup the GameLift Agent
- Download and extract the FPSTemplateServer game server binary
- Set executable permissions on the server binaries
- Configure CloudWatch logging
- Start the GameLift Agent with appropriate parameters

### `update_game_server.sh`

This script allows you to deploy updated versions of your game server to the existing development instance without recreating the entire infrastructure. It:

1. Downloads the latest `FPSTemplateServer.zip` from S3
2. Uploads it to the deployment bucket
3. Triggers the SSM deployment process on the EC2 instance
4. The GameLift Agent automatically restarts with the new server version

Use this script whenever you make changes to your game server code and want to test them on the dev instance.

### `cleanup.sh`

This script safely deletes all AWS resources created by the deployment. It removes:

1. GameLift Fleet and Location
2. EC2 instance
3. Security groups
4. IAM roles, instance profiles, and policies
5. S3 bucket and contents
6. Local downloaded files

**Important**: This script will prompt for confirmation before deleting resources. Run this when you're completely done with the development instance to avoid ongoing AWS charges.

## Usage

### Initial Deployment

1. **Upload your game server to S3**: Build your FPS Template server for Linux and upload it to S3 at the path `builders/Linux/Server/FPSTemplate/FPSTemplateServer.zip`

2. **Configure the script**: Edit `deploy_dev_instance.sh` and update these variables:
   ```bash
   BUCKET_NAME="your-unique-bucket-name"           # For deployment resources
   SOURCE_BUCKET_NAME="your-source-bucket-name"     # Where FPSTemplateServer.zip is stored
   ```

3. **Run the deployment script**:
   ```bash
   ./deploy_dev_instance.sh
   ```

4. **Monitor the deployment**: The script will:
   - Download your game server from S3
   - Create AWS infrastructure
   - Deploy the server to EC2
   - Run a test game session
   - Complete in about 5-7 minutes

5. **Verify the setup**: The script will automatically test the deployment by creating a game session. You should see:
   ```
   ✅ SUCCESS! Game session created: arn:aws:gamelift:...
   ```

### Deploying Updates

After making changes to your game server, deploy updates with:

```bash
./update_game_server.sh
```

This will download the latest version from S3 and deploy it to your development instance without recreating the infrastructure.

### Cleanup

When you're done with the development instance and want to delete all resources:

```bash
./cleanup.sh
```

This will:
- Prompt for confirmation (type `yes` to proceed)
- Delete the GameLift Fleet and Location
- Terminate the EC2 instance
- Remove all IAM roles and policies
- Delete the S3 bucket and contents
- Clean up local files

**Important**: This action cannot be undone. Make sure you've saved any logs or data you need before running cleanup.

## Configuration Parameters

The deployment scripts automatically configure most parameters. You typically only need to set:

### In `deploy_dev_instance.sh` and `update_game_server.sh`:
- `BUCKET_NAME`: Your unique S3 bucket name for deployment resources
- `SOURCE_BUCKET_NAME`: S3 bucket containing your game server builds

### Automatically configured in `dev-game-server-setup-and-deployment.json`:
- `FLEET_ID`: Automatically replaced by the deployment script
- `S3_BUCKET`: Automatically replaced by the deployment script
- Game server executable path: `/local/game/LinuxServer/FPSTemplateServer`
- Server port: 1935 (TCP)
- Location: `custom-mygame-dev-location`

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

### Common Issues

1. **SERVER_PROCESS_INVALID_PATH Error**
   - **Cause**: The LaunchPath in the fleet configuration doesn't match the actual executable path
   - **Solution**: The script now correctly sets the path to `/local/game/LinuxServer/FPSTemplateServer`
   - **Verify**: SSH into the instance and check: `ls -la /local/game/LinuxServer/`

2. **Game Session Creation Fails**
   - **Cause**: Server hasn't fully started yet
   - **Solution**: Wait 2-3 minutes after deployment, then try creating a game session again
   - **Check**: `aws gamelift describe-instances --fleet-id <FLEET_ID>`

3. **Java Not Found**
   - **Cause**: Wrong Java package for Amazon Linux 2023
   - **Solution**: Script now installs `java-23-amazon-corretto-headless`
   - **Manual install**: `sudo yum install java-23-amazon-corretto-headless -y`

4. **Permission Denied on Executable**
   - **Cause**: Server binary doesn't have execute permissions
   - **Solution**: Script now runs `chmod +x LinuxServer/FPSTemplateServer` after extraction
   - **Manual fix**: SSH into instance and run: `chmod +x /local/game/LinuxServer/FPSTemplateServer`

5. **Can't Find dev-game-server-setup-and-deployment.json**
   - **Cause**: Running script from different directory
   - **Solution**: Script now auto-detects its location and changes directory
   - **Alternative**: Run script from its own directory

### Checking Server Status

```bash
# SSH into the instance
aws ssm start-session --target <INSTANCE_ID>

# Check if GameLift Agent is running
ps aux | grep GameLiftAgent

# Check if game server is running
ps aux | grep FPSTemplate

# Check server logs
tail -f /local/game/logs/myserver1935.log

# Check fleet events
aws gamelift describe-fleet-events --fleet-id <FLEET_ID> --limit 10
```

### Getting Fleet Information

```bash
# Get Fleet ID
FLEET_ID=$(aws gamelift describe-fleet-attributes --query 'FleetAttributes[?Name==`MyGame-Test-Fleet`].FleetId' --output text)

# Create a test game session
aws gamelift create-game-session \
  --fleet-id $FLEET_ID \
  --region us-east-1 \
  --maximum-player-session-count 5 \
  --location custom-mygame-dev-location
```

## Cleanup

To clean up all resources created by the deployment, use the provided cleanup script:

```bash
./cleanup.sh
```

The script will automatically delete all resources including:
- GameLift fleet and location
- EC2 instance and security group
- IAM roles, instance profiles, and policies
- S3 bucket and contents
- Local files

You will be prompted for confirmation before any resources are deleted.

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
