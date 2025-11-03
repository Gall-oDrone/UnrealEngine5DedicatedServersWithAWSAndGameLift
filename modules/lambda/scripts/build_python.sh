#!/bin/bash

# Build script for Python Lambda function
# This script packages the Python Lambda function for deployment

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the module path from argument or use current directory
MODULE_PATH="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_DIR="$MODULE_PATH/python"
SRC_DIR="$PYTHON_DIR/src"
BUILD_DIR="$PYTHON_DIR/build"

echo -e "${YELLOW}Building Python Lambda function...${NC}"

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}Cleaning previous build...${NC}"
    rm -rf "$BUILD_DIR"
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# Copy Python source files
echo -e "${YELLOW}Copying Python source files...${NC}"
cp -r "$SRC_DIR"/* "$BUILD_DIR"/

# Install dependencies
if [ -f "$SRC_DIR/requirements.txt" ]; then
    echo -e "${YELLOW}Installing Python dependencies...${NC}"
    # Check if pip is available
    if command -v pip3 &> /dev/null; then
        pip3 install -r "$SRC_DIR/requirements.txt" -t "$BUILD_DIR" --quiet
        echo -e "${GREEN}✓ Dependencies installed${NC}"
    else
        echo -e "${RED}Warning: pip3 not found. Skipping dependency installation.${NC}"
        echo -e "${YELLOW}Consider using a Docker container for consistent builds${NC}"
    fi
fi

echo -e "${GREEN}✓ Python Lambda build complete!${NC}"
echo -e "${GREEN}✓ Build output: $BUILD_DIR${NC}"

