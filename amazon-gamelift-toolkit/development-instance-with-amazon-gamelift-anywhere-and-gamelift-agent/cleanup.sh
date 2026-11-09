#!/bin/bash

# Get the directory where this script is located and cd into it
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "============================================"
echo "GameLift Anywhere Development Instance Cleanup"
echo "============================================"
echo ""
echo "⚠️  WARNING: This will delete all resources created by deploy_dev_instance.sh"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup process..."
echo ""

# Configuration - Update these if you changed them in deploy_dev_instance.sh
BUCKET_NAME="my-unique-bucket-name"  # TODO: Set this to match your deploy script
FLEET_NAME="MyGame-Test-Fleet"
LOCATION_NAME="custom-mygame-dev-location"

########## 1. DELETE FLEET ################

echo "Step 1: Deleting GameLift Fleet..."
FLEET_ID=$(aws gamelift describe-fleet-attributes --query "FleetAttributes[?Name=='$FLEET_NAME'].FleetId" --output text 2>/dev/null)

if [ ! -z "$FLEET_ID" ]; then
    echo "Found Fleet ID: $FLEET_ID"
    
    # Delete the fleet
    aws gamelift delete-fleet --fleet-id $FLEET_ID
    echo "✅ Fleet deletion initiated. Fleet ID: $FLEET_ID"
    echo "   Note: Fleet deletion may take a few minutes to complete."
else
    echo "⚠️  Fleet '$FLEET_NAME' not found or already deleted."
fi

echo ""

########## 2. DELETE LOCATION ################

echo "Step 2: Deleting GameLift Location..."

# Wait a bit for fleet deletion to process
sleep 5

# Check if location exists and delete it
LOCATION_EXISTS=$(aws gamelift describe-fleet-location-attributes --fleet-id $FLEET_ID --locations $LOCATION_NAME 2>/dev/null)

if [ $? -eq 0 ]; then
    aws gamelift delete-location --location-name $LOCATION_NAME 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✅ Location deleted: $LOCATION_NAME"
    else
        echo "⚠️  Location may still be in use or already deleted."
    fi
else
    # Try to delete anyway
    aws gamelift delete-location --location-name $LOCATION_NAME 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✅ Location deleted: $LOCATION_NAME"
    else
        echo "⚠️  Location '$LOCATION_NAME' not found or already deleted."
    fi
fi

echo ""

########## 3. TERMINATE EC2 INSTANCE ################

echo "Step 3: Terminating EC2 Instance..."
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=AmazonGameLiftDevInstance" "Name=instance-state-name,Values=running,stopped" --query "Reservations[*].Instances[*].InstanceId" --output text)

INSTANCE_TERMINATED=false
if [ ! -z "$INSTANCE_ID" ]; then
    echo "Found Instance ID: $INSTANCE_ID"
    aws ec2 terminate-instances --instance-ids $INSTANCE_ID
    echo "✅ EC2 instance termination initiated: $INSTANCE_ID"
    echo "   Waiting for instance to fully terminate (this may take 1-2 minutes)..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
    echo "✅ EC2 instance terminated successfully"
    INSTANCE_TERMINATED=true
else
    echo "⚠️  EC2 instance 'AmazonGameLiftDevInstance' not found or already terminated."
    INSTANCE_TERMINATED=true
fi

echo ""

########## 4. DELETE SECURITY GROUP ################

echo "Step 4: Deleting Security Group..."

# Wait for instance to fully terminate
sleep 10

SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=game-server-sg" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)

if [ ! -z "$SECURITY_GROUP_ID" ] && [ "$SECURITY_GROUP_ID" != "None" ]; then
    echo "Found Security Group ID: $SECURITY_GROUP_ID"
    aws ec2 delete-security-group --group-id $SECURITY_GROUP_ID
    if [ $? -eq 0 ]; then
        echo "✅ Security group deleted: $SECURITY_GROUP_ID"
    else
        echo "⚠️  Could not delete security group. It may still be in use. Wait a few minutes and try:"
        echo "   aws ec2 delete-security-group --group-id $SECURITY_GROUP_ID"
    fi
else
    echo "⚠️  Security group 'game-server-sg' not found or already deleted."
fi

echo ""

########## 5. REMOVE IAM RESOURCES ################

echo "Step 5: Removing IAM Resources..."

# Ensure EC2 instance is fully terminated before touching IAM
if [ "$INSTANCE_TERMINATED" = true ]; then
    echo "   EC2 instance confirmed terminated, proceeding with IAM cleanup..."
    
    # Additional wait to ensure all AWS resources are fully released
    echo "   Waiting for all EC2 resources to be fully released..."
    sleep 10
else
    echo "⚠️  WARNING: EC2 instance status unknown. Proceeding with caution..."
fi

# Remove role from instance profile
aws iam remove-role-from-instance-profile --instance-profile-name GameLiftDevInstanceProfile --role-name DevelopmentGameServerInstanceRole 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Removed role from instance profile"
fi

# Delete instance profile
aws iam delete-instance-profile --instance-profile-name GameLiftDevInstanceProfile 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Instance profile deleted: GameLiftDevInstanceProfile"
fi

# Wait a bit more to ensure instance profile is fully released
echo "   Waiting for instance profile to be fully released..."
sleep 5

# Get account ID for custom policy ARN
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

# Detach AWS managed policies from role
echo "   Detaching AWS managed policies from role..."
aws iam detach-role-policy --role-name DevelopmentGameServerInstanceRole --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null
aws iam detach-role-policy --role-name DevelopmentGameServerInstanceRole --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy 2>/dev/null
aws iam detach-role-policy --role-name DevelopmentGameServerInstanceRole --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess 2>/dev/null

# Detach and delete custom GameLiftFullAccess policy
if [ ! -z "$ACCOUNT_ID" ]; then
    CUSTOM_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/GameLiftFullAccess"
    echo "   Detaching custom policy: GameLiftFullAccess"
    
    # Detach the policy from the role
    aws iam detach-role-policy --role-name DevelopmentGameServerInstanceRole --policy-arn $CUSTOM_POLICY_ARN 2>/dev/null
    
    # Wait for detachment to propagate
    echo "   Waiting for policy detachment to complete..."
    sleep 5
    
    # Check if policy exists before deleting
    POLICY_EXISTS=$(aws iam get-policy --policy-arn $CUSTOM_POLICY_ARN 2>/dev/null)
    if [ $? -eq 0 ]; then
        # Retry deletion up to 3 times with delays
        MAX_RETRIES=3
        RETRY_COUNT=0
        POLICY_DELETED=false
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$POLICY_DELETED" = false ]; do
            aws iam delete-policy --policy-arn $CUSTOM_POLICY_ARN 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "✅ Custom policy deleted: GameLiftFullAccess"
                POLICY_DELETED=true
            else
                RETRY_COUNT=$((RETRY_COUNT + 1))
                if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                    echo "   Policy still attached, waiting 10 seconds before retry $((RETRY_COUNT + 1))/$MAX_RETRIES..."
                    sleep 10
                fi
            fi
        done
        
        if [ "$POLICY_DELETED" = false ]; then
            echo "⚠️  Failed to delete policy after $MAX_RETRIES attempts: GameLiftFullAccess"
            echo "   The policy may still be attached. Wait a few minutes and delete manually:"
            echo "   aws iam delete-policy --policy-arn $CUSTOM_POLICY_ARN"
        fi
    else
        echo "⚠️  Custom policy 'GameLiftFullAccess' not found or already deleted"
    fi
else
    echo "⚠️  Could not determine AWS Account ID. Skipping custom policy deletion."
fi

# Delete role
echo "   Deleting IAM role..."
aws iam delete-role --role-name DevelopmentGameServerInstanceRole 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ IAM role deleted: DevelopmentGameServerInstanceRole"
else
    echo "⚠️  IAM role 'DevelopmentGameServerInstanceRole' not found or already deleted"
fi

echo ""

########## 6. DELETE S3 BUCKET ################

echo "Step 6: Deleting S3 Bucket..."

# Check if bucket exists
aws s3 ls s3://$BUCKET_NAME 2>/dev/null
if [ $? -eq 0 ]; then
    echo "Found S3 bucket: $BUCKET_NAME"
    echo "   Emptying bucket..."
    aws s3 rm s3://$BUCKET_NAME --recursive
    echo "   Deleting bucket..."
    aws s3 rb s3://$BUCKET_NAME
    if [ $? -eq 0 ]; then
        echo "✅ S3 bucket deleted: $BUCKET_NAME"
    else
        echo "⚠️  Could not delete S3 bucket. You may need to delete it manually:"
        echo "   aws s3 rb s3://$BUCKET_NAME --force"
    fi
else
    echo "⚠️  S3 bucket '$BUCKET_NAME' not found or already deleted."
fi

echo ""

########## 7. CLEAN UP LOCAL FILES ################

echo "Step 7: Cleaning up local files..."

if [ -f "./FPSTemplateServer.zip" ]; then
    rm -f ./FPSTemplateServer.zip
    echo "✅ Removed local FPSTemplateServer.zip"
fi

if [ -d "./amazon-gamelift-agent" ]; then
    rm -rf ./amazon-gamelift-agent
    echo "✅ Removed local GameLift Agent directory"
fi

# Remove backup files created by sed
rm -f ./dev-game-server-setup-and-deployment.json-e 2>/dev/null

echo ""
echo "============================================"
echo "Cleanup Complete!"
echo "============================================"
echo ""
echo "Summary of deleted resources:"
echo "  ✅ GameLift Fleet: $FLEET_NAME"
echo "  ✅ GameLift Location: $LOCATION_NAME"
echo "  ✅ EC2 Instance: AmazonGameLiftDevInstance"
echo "  ✅ Security Group: game-server-sg"
echo "  ✅ IAM Role: DevelopmentGameServerInstanceRole"
echo "  ✅ IAM Instance Profile: GameLiftDevInstanceProfile"
echo "  ✅ IAM Policy: GameLiftFullAccess"
echo "  ✅ S3 Bucket: $BUCKET_NAME"
echo "  ✅ Local files cleaned up"
echo ""
echo "Note: Some resources may take a few minutes to fully delete."
echo "You can verify deletion in the AWS Console."
echo ""

