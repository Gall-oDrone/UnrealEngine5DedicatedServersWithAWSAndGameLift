#!/bin/bash

# Get the directory where this script is located and cd into it
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# TODO: Replace this with a globally unique name!
BUCKET_NAME="my-unique-bucket-name"

# TODO: Replace this with your source bucket containing the game server build
SOURCE_BUCKET_NAME="your-source-bucket-name"


########## 1. DOWNLOAD GAME SERVER BUILD FROM S3 ################

# Download the FPS Template Server build from S3
echo "Downloading FPSTemplateServer.zip from S3..."
aws s3 cp s3://$SOURCE_BUCKET_NAME/builders/Linux/Server/FPSTemplate/FPSTemplateServer.zip ./FPSTemplateServer.zip

if [ ! -f "./FPSTemplateServer.zip" ]; then
    echo "Failed to download FPSTemplateServer.zip from S3"
    exit 1
fi

echo "Successfully downloaded FPSTemplateServer.zip"


########## 2. CHECK THAT TOOLS ARE INSTALLED AND S3 BUCKET IS NOT OWNED BY SOMEONE ELSE ################

# Double check that java is installed and exit if not
if which java > /dev/null 2>&1; then
    echo "Java is installed"
else
    echo "Java not installed yet"
    exit 1
fi

# Double that Maven is installed and exit if not
if which mvn > /dev/null 2>&1; then
    echo "maven is installed"
else
    echo "Maven not installed yet"
    exit 1
fi

# Set the current region for the AWS CLI is us-east-1
echo "Setting region to us-east-1 for the AWS CLI"
aws configure set region us-east-1

# Check that the S3 bucket is not already owned by someone else
bucketstatus=$(aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>&1)
if echo "${bucketstatus}" | grep 'Forbidden';
then
  echo "Bucket is already owned by someone else, edit deploy_dev_instance.sh to set a unique name"
  exit 1
elif echo "${bucketstatus}" | grep 'Bad Request';
then
  echo "Bucket name specified is less than 3 or greater than 63 characters"
  exit 1
else
  echo "You already have this bucket in your account, continue..."
fi


########## 3. CREATE THE S3 BUCKET, BUILD THE AGENT AND UPLOAD AGENT AND GAME SERVER BINARY TO S3 ################

# Create the S3 bucket
aws s3 mb s3://$BUCKET_NAME

# Build the Amazon GameLift Agent if it doesn't exist yet
agent_file="amazon-gamelift-agent/target/GameLiftAgent-1.0.jar"
if [ ! -f "$agent_file" ]; then
    git clone https://github.com/aws/amazon-gamelift-agent.git
    cd amazon-gamelift-agent/
    mvn clean compile assembly:single
    cd ..
else
    echo "Agent already built"
fi

# Copy the GameLift agent to the bucket
agent_file="amazon-gamelift-agent/target/GameLiftAgent-1.0.jar"
if [ ! -f "$agent_file" ]; then
    echo "Error: $agent_file does not exist"
    exit 1
fi
aws s3 cp "$agent_file" "s3://$BUCKET_NAME"

# Copy over the FPS Template Server build
aws s3 cp ./FPSTemplateServer.zip s3://$BUCKET_NAME

########## 4. CREATE THE GAMELIFT RESOURCES ################

# Create the Amazon GameLift Anywhere location
LOCATION_NAME="custom-mygame-dev-location"
aws gamelift create-location --location-name $LOCATION_NAME

# Create the Amazon GameLift Anywhere fleet if it doesn't exist yet
FLEET_NAME="MyGame-Test-Fleet"
FLEET_ID=$(aws gamelift describe-fleet-attributes --query "FleetAttributes[?Name=='$FLEET_NAME'].FleetId" --output text 2>/dev/null)
if [ -z "$FLEET_ID" ]; then
    echo "Creating fleet: $FLEET_NAME"
    FLEET_ID=$(aws gamelift create-fleet --name $FLEET_NAME --compute-type ANYWHERE \
             --locations "Location=$LOCATION_NAME" \
             --runtime-configuration "ServerProcesses=[{LaunchPath=/local/game/LinuxServer/FPSTemplateServer,ConcurrentExecutions=1,Parameters=-logFile /local/game/logs/myserver1935.log -port 1935}]" \
             --anywhere-configuration Cost=0.2 \
             --query 'FleetAttributes.FleetId' --output text)
else
    echo "Fleet $FLEET_NAME already exists."
fi


########## 5. CREATE THE EC2 INSTANCE AND RELATED RESOURCES ################

# Only create the IAM and EC2 resources if we don't have an AmazonGameLiftDevInstance already
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=AmazonGameLiftDevInstance" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text)
if [ -z "$INSTANCE_ID" ]; then

    # Create the IAM Role and Instance Profile for the EC2 instance
    echo "Creating IAM role..."
    aws iam create-role --role-name DevelopmentGameServerInstanceRole \
        --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
        --description "Role for EC2 instance to run Amazon GameLift Agent" \
        --query 'Role.Arn' 2>/dev/null
    
    # Wait for role to be available
    sleep 3
    
    # Create or get the custom GameLift policy
    echo "Setting up GameLift policy..."
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    gamelift_policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/GameLiftFullAccess"
    
    # Try to create the policy, if it fails it likely already exists
    aws iam create-policy \
        --policy-name GameLiftFullAccess \
        --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["gamelift:*"],"Resource":"*"}]}' \
        --query 'Policy.Arn' \
        --output text 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "Created new GameLiftFullAccess policy"
    else
        echo "GameLiftFullAccess policy already exists, using existing policy"
    fi
    
    # Attach all policies to the role
    echo "Attaching policies to role..."
    aws iam attach-role-policy --role-name DevelopmentGameServerInstanceRole --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    aws iam attach-role-policy --role-name DevelopmentGameServerInstanceRole --policy-arn "$gamelift_policy_arn"
    aws iam attach-role-policy --role-name DevelopmentGameServerInstanceRole --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
    aws iam attach-role-policy --role-name DevelopmentGameServerInstanceRole --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
    
    # Create instance profile
    echo "Creating instance profile..."
    aws iam create-instance-profile --instance-profile-name GameLiftDevInstanceProfile 2>/dev/null
    
    # Wait for the instance profile to be created
    sleep 5
    
    # Add role to instance profile
    aws iam add-role-to-instance-profile --role-name DevelopmentGameServerInstanceRole --instance-profile-name GameLiftDevInstanceProfile 2>/dev/null
    
    # Wait for everything to propagate
    echo "Waiting for IAM resources to propagate..."
    sleep 10

    # Create a Security Group for the EC2 instance in the Default VPC
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name game-server-sg \
        --description "Security group for the game server" \
        --vpc-id $(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text) \
        --query 'GroupId' --output text)

    # Allow inbound access for port 1935 for TCP
    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port 1935 \
        --cidr 0.0.0.0/0 \
        --query 'SecurityGroupRules[0].SecurityGroupRuleId'

    # Create the EC2 instance and wait for it to start
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
        --instance-type m6i.large \
        --iam-instance-profile Name="GameLiftDevInstanceProfile" \
        --associate-public-ip-address \
        --security-group-ids $SECURITY_GROUP_ID \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=AmazonGameLiftDevInstance}]' \
        --query 'Instances[0].InstanceId' \
        --output text)
    echo "Instance created with ID: $INSTANCE_ID"
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID
else
    echo "Instance with ID $INSTANCE_ID already exists."
fi


########## 6. DEPLOY THE AGENT AND GAME SERVER BINARY TO THE EC2 INSTANCE AND CONFIGURE IT WITH SSM ################

# Configure and run the SSM command to install and start our game server
sed -i -e "s/your-fleet-id/$FLEET_ID/g" dev-game-server-setup-and-deployment.json
sed -i -e "s/your-bucket-name/$BUCKET_NAME/g" dev-game-server-setup-and-deployment.json

# Wait 15 seconds before sending the SSM command to make sure the SSM agent on the instance is ready
sleep 15

echo "EC2 instance is ready, sending SSM command to install and start the game server..."

COMMAND_ID=$(aws ssm send-command --document-name "AWS-RunShellScript" \
--targets "Key=InstanceIds,Values=$INSTANCE_ID" \
--cli-input-json file://dev-game-server-setup-and-deployment.json \
--query 'Command.CommandId' --output text)

echo "SSM Command ID: $COMMAND_ID"
echo "Waiting for deployment to complete (this may take 2-3 minutes)..."
sleep 120

echo "All done! You should be able to start a game session now."


########## 7. TEST THE DEPLOYMENT ################

echo ""
echo "Testing the deployment by creating a game session..."
echo ""

# Wait a bit more for the agent to fully register
sleep 30

# Create a test game session
GAME_SESSION_ID=$(aws gamelift create-game-session \
--fleet-id $FLEET_ID \
--region us-east-1 \
--maximum-player-session-count 5 \
--location custom-mygame-dev-location \
--game-properties "[{\"Key\":\"SomeKey\",\"Value\":\"SomeValue\"}]" \
--query 'GameSession.GameSessionId' --output text 2>&1)

if [[ $GAME_SESSION_ID == arn:* ]]; then
    echo "✅ SUCCESS! Game session created: $GAME_SESSION_ID"
    echo ""
    echo "You can view the game session details with:"
    echo "aws gamelift describe-game-sessions --game-session-id $GAME_SESSION_ID"
else
    echo "⚠️  Game session creation failed or is pending. Error: $GAME_SESSION_ID"
    echo ""
    echo "This is normal if the server is still starting up. Wait a minute and try again:"
    echo "aws gamelift create-game-session --fleet-id $FLEET_ID --region us-east-1 --maximum-player-session-count 5 --location custom-mygame-dev-location"
fi

echo ""
echo "============================================"
echo "Deployment complete!"
echo "============================================"
echo "Fleet ID: $FLEET_ID"
echo "Instance ID: $INSTANCE_ID"
echo "Location: $LOCATION_NAME"
echo ""
echo "To check server logs:"
echo "  aws ssm start-session --target $INSTANCE_ID"
echo "  tail -f /local/game/logs/myserver1935.log"
echo ""
echo "To check compute status:"
echo "  aws gamelift describe-instances --fleet-id $FLEET_ID"
echo ""
echo "To deploy an updated version of the game server:"
echo "  ./update_game_server.sh"
echo ""
echo "To clean up all resources (delete everything):"
echo "  ./cleanup.sh"
echo ""

# Restore the json file to template state
sed -i -e "s/$FLEET_ID/your-fleet-id/g" dev-game-server-setup-and-deployment.json
sed -i -e "s/$BUCKET_NAME/your-bucket-name/g" dev-game-server-setup-and-deployment.json
