#!/bin/bash

# Build script for Go Lambda function
# This script builds the Go Lambda function for deployment

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the module path from argument or use current directory
MODULE_PATH="${1:-$(pwd)}"
GO_DIR="$MODULE_PATH/go"
SRC_DIR="$GO_DIR/src"
BUILD_DIR="$GO_DIR/build"

echo -e "${YELLOW}Building Go Lambda function...${NC}"

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed${NC}"
    echo -e "${YELLOW}Please install Go from https://golang.org/dl/${NC}"
    exit 1
fi

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}Cleaning previous build...${NC}"
    rm -rf "$BUILD_DIR"
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# Go to source directory
cd "$SRC_DIR"

# Download dependencies
echo -e "${YELLOW}Downloading Go dependencies...${NC}"
go mod download
echo -e "${GREEN}✓ Dependencies downloaded${NC}"

# Build for Linux AMD64 (Lambda environment)
echo -e "${YELLOW}Building Go binary for Linux AMD64...${NC}"
GOOS=linux GOARCH=amd64 go build -o "$BUILD_DIR/bootstrap" .

if [ -f "$BUILD_DIR/bootstrap" ]; then
    echo -e "${GREEN}✓ Go Lambda build complete!${NC}"
    echo -e "${GREEN}✓ Binary: $BUILD_DIR/bootstrap${NC}"
    
    # Show binary info
    file "$BUILD_DIR/bootstrap"
    ls -lh "$BUILD_DIR/bootstrap"
else
    echo -e "${RED}Error: Build failed${NC}"
    exit 1
fi

