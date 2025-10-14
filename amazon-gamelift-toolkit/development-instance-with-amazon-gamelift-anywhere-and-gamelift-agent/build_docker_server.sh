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

echo "Building the server and copying output to LinuxServerBuild..."
echo "Working directory: $(pwd)"
echo ""

# Build and extract files following the pattern from the referenced buildserver.sh
docker buildx build --platform=linux/amd64 --output=../LinuxServerBuild --target=server .

if [ $? -eq 0 ]; then
    echo ""
    echo "Build completed successfully!"
    echo ""
    
    # Remove .cpp and .h files as specified in the referenced script
    echo "Cleaning up source files..."
    rm ../LinuxServerBuild/*.cpp 2>/dev/null || true
    rm ../LinuxServerBuild/*.h 2>/dev/null || true
    
    # Zip the LinuxServerBuild folder
    echo "Creating zip archive of the server build..."
    cd ..
    zip -r LinuxServerBuild.zip LinuxServerBuild/
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "============================================"
        echo "Server build completed successfully!"
        echo "Output directory: LinuxServerBuild/"
        echo "Zip archive: LinuxServerBuild.zip"
        echo "============================================"
        echo ""
        echo "The server files have been extracted and zipped for GameLift deployment."
        echo "You can now upload LinuxServerBuild.zip to S3."
    else
        echo ""
        echo "Error: Failed to create zip archive!"
        echo "Server files are available in LinuxServerBuild/ directory."
        exit 1
    fi
else
    echo ""
    echo "Error: Docker buildx build failed!"
    echo "Please check the Dockerfile and ensure all dependencies are available."
    exit 1
fi
