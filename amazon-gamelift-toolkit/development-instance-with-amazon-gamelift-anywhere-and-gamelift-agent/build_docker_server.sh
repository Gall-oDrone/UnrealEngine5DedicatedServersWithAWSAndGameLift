#!/bin/bash

# Get the directory where this script is located and cd into it
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "============================================"
echo "Building Docker Game Server"
echo "============================================"
echo ""

# TODO: Replace this with your actual S3 bucket name
SOURCE_BUCKET_NAME="your-source-bucket-name"

# Configuration
S3_KEY_PATH="builders/Linux/Server/FPSTemplate/FPSTemplateServer"
CONTAINER_DIR="./container"

echo "Copying FPSTemplateServer from S3..."
echo "Source: s3://$SOURCE_BUCKET_NAME/$S3_KEY_PATH"
echo "Destination: $CONTAINER_DIR/FPSTemplateServer"
echo ""

# Create container directory if it doesn't exist
mkdir -p "$CONTAINER_DIR"

# Copy the FPSTemplateServer from S3
aws s3 cp "s3://$SOURCE_BUCKET_NAME/$S3_KEY_PATH" "$CONTAINER_DIR/FPSTemplateServer"

if [ ! -f "$CONTAINER_DIR/FPSTemplateServer" ]; then
    echo "Error: Failed to download FPSTemplateServer from S3"
    echo "Please check your S3 bucket name and ensure the file exists at: s3://$SOURCE_BUCKET_NAME/$S3_KEY_PATH"
    exit 1
fi

echo "Successfully downloaded FPSTemplateServer"
echo ""

# Make the file executable
echo "Making FPSTemplateServer executable..."
chmod +x "$CONTAINER_DIR/FPSTemplateServer"
echo "FPSTemplateServer is now executable"
echo ""

# Change to container directory for Docker build
cd "$CONTAINER_DIR"

echo "Building Docker image..."
echo "Working directory: $(pwd)"
echo ""

# Build the Docker image following the pattern from the referenced buildserver.sh
# Note: Ignoring the rm commands for .cpp and .h files as requested
docker build -t gamelift-server:latest .

if [ $? -eq 0 ]; then
    echo ""
    echo "============================================"
    echo "Docker image built successfully!"
    echo "Image name: gamelift-server:latest"
    echo "============================================"
    echo ""
    echo "You can now run the container with:"
    echo "  docker run gamelift-server:latest"
    echo ""
    echo "The container structure is now ready for GameLift deployment."
else
    echo ""
    echo "Error: Docker build failed!"
    echo "Please check the Dockerfile and ensure all dependencies are available."
    exit 1
fi
