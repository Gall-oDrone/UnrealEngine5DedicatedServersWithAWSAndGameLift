#!/bin/bash

# Get the directory where this script is located and cd into it
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "============================================"
echo "Deploying an updated version of the game server"
echo "============================================"
echo ""

# TODO: Replace this with your actual values
BUCKET_NAME="my-unique-bucket-name"
SOURCE_BUCKET_NAME="your-source-bucket-name"

# Get the Fleet ID
FLEET_NAME="MyGame-Test-Fleet"
FLEET_ID=$(aws gamelift describe-fleet-attributes --query "FleetAttributes[?Name=='$FLEET_NAME'].FleetId" --output text 2>/dev/null)

if [ -z "$FLEET_ID" ]; then
    echo "Error: Fleet $FLEET_NAME not found. Please run deploy_dev_instance.sh first."
    exit 1
fi

echo "Found Fleet ID: $FLEET_ID"

# Get the Instance ID
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=AmazonGameLiftDevInstance" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text)

if [ -z "$INSTANCE_ID" ]; then
    echo "Error: AmazonGameLiftDevInstance not found or not running."
    exit 1
fi

echo "Found Instance ID: $INSTANCE_ID"
echo ""

########## DOWNLOAD UPDATED GAME SERVER BUILD ################

echo "Downloading updated FPSTemplateServer from S3..."
aws s3 cp s3://$SOURCE_BUCKET_NAME/builders/Linux/Server/FPSTemplate/FPSTemplateServer ./FPSTemplateServer

if [ ! -f "./FPSTemplateServer" ]; then
    echo "Failed to download FPSTemplateServer from S3"
    exit 1
fi

echo "Successfully downloaded FPSTemplateServer"

# Make the server executable
chmod +x ./FPSTemplateServer

# Upload the updated build to the deployment bucket
echo "Uploading updated build to deployment bucket..."
aws s3 cp ./FPSTemplateServer s3://$BUCKET_NAME

echo ""
echo "========================================"
echo "Deploying to EC2 instance..."
echo "========================================"
echo ""

# Configure and run the SSM command to update the game server
sed -i -e "s/your-fleet-id/$FLEET_ID/g" dev-game-server-setup-and-deployment.json
sed -i -e "s/your-bucket-name/$BUCKET_NAME/g" dev-game-server-setup-and-deployment.json

# Send the deployment command
COMMAND_ID=$(aws ssm send-command --document-name "AWS-RunShellScript" \
--targets "Key=InstanceIds,Values=$INSTANCE_ID" \
--cli-input-json file://dev-game-server-setup-and-deployment.json \
--query 'Command.CommandId' --output text)

echo "SSM Command ID: $COMMAND_ID"
echo ""
echo "Deployment initiated. The server will:"
echo "  1. Download the updated build"
echo "  2. Stop the current GameLift agent and server"
echo "  3. Extract the new build"
echo "  4. Restart the GameLift agent"
echo "  5. The agent will automatically start the new server"
echo ""
echo "This process takes about 2-3 minutes."
echo ""
echo "To monitor the deployment:"
echo "  aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $INSTANCE_ID"
echo ""
echo "To check server logs after deployment:"
echo "  aws ssm start-session --target $INSTANCE_ID"
echo "  tail -f /local/game/logs/myserver1935.log"
echo ""
echo "To verify the server is running:"
echo "  aws gamelift describe-instances --fleet-id $FLEET_ID"
echo ""

# Restore the json file to template state
sed -i -e "s/$FLEET_ID/your-fleet-id/g" dev-game-server-setup-and-deployment.json
sed -i -e "s/$BUCKET_NAME/your-bucket-name/g" dev-game-server-setup-and-deployment.json

echo "Update deployment complete!"
echo ""
echo "To clean up all resources when done:"
echo "  ./cleanup.sh"

