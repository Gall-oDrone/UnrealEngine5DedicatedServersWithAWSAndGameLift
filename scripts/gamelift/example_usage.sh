#!/bin/bash

# Example usage of the GameLift SDK Authentication Token Generator
# This script demonstrates different ways to use the generate_auth_token.sh script

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATE_SCRIPT="$SCRIPT_DIR/generate_auth_token.sh"

# Example configuration - Replace with your actual values
EXAMPLE_FLEET_ID="fleet-12345678-1234-1234-1234-123456789012"
EXAMPLE_COMPUTE_NAME="MyGameServer"
EXAMPLE_REGION="us-east-1"

print_info "GameLift SDK Authentication Token Generator - Example Usage"
echo ""

# Example 1: Basic usage - just get the token
print_info "Example 1: Basic usage - Get token only"
echo "Command: $GENERATE_SCRIPT --fleet-id $EXAMPLE_FLEET_ID --compute-name $EXAMPLE_COMPUTE_NAME"
echo "Output: [AUTH_TOKEN]"
echo ""

# Example 2: Get token as environment variable export
print_info "Example 2: Get token as environment variable export"
echo "Command: $GENERATE_SCRIPT --fleet-id $EXAMPLE_FLEET_ID --compute-name $EXAMPLE_COMPUTE_NAME --output env"
echo "Output: export GAMELIFT_SDK_AUTH_TOKEN=\"[AUTH_TOKEN]\""
echo ""

# Example 3: Export token directly to environment
print_info "Example 3: Export token directly to environment"
echo "Command: $GENERATE_SCRIPT --fleet-id $EXAMPLE_FLEET_ID --compute-name $EXAMPLE_COMPUTE_NAME --export"
echo "Effect: Sets GAMELIFT_SDK_AUTH_TOKEN environment variable in current shell"
echo ""

# Example 4: Save token to file
print_info "Example 4: Save token to file"
echo "Command: $GENERATE_SCRIPT --fleet-id $EXAMPLE_FLEET_ID --compute-name $EXAMPLE_COMPUTE_NAME --save /tmp/gamelift_token.txt"
echo "Effect: Saves token to /tmp/gamelift_token.txt with secure permissions"
echo ""

# Example 5: Get token as JSON
print_info "Example 5: Get token as JSON"
echo "Command: $GENERATE_SCRIPT --fleet-id $EXAMPLE_FLEET_ID --compute-name $EXAMPLE_COMPUTE_NAME --output json"
echo "Output: {\"AuthToken\": \"[AUTH_TOKEN]\", \"FleetId\": \"$EXAMPLE_FLEET_ID\", \"ComputeName\": \"$EXAMPLE_COMPUTE_NAME\", \"Region\": \"$EXAMPLE_REGION\"}"
echo ""

# Example 6: Using environment variables
print_info "Example 6: Using environment variables"
echo "Commands:"
echo "  export GAMELIFT_FLEET_ID=\"$EXAMPLE_FLEET_ID\""
echo "  export GAMELIFT_COMPUTE_NAME=\"$EXAMPLE_COMPUTE_NAME\""
echo "  $GENERATE_SCRIPT"
echo "Effect: Uses environment variables instead of command line arguments"
echo ""

# Example 7: Integration with game server startup
print_info "Example 7: Integration with game server startup"
echo "#!/bin/bash"
echo "# Get auth token and start game server"
echo "AUTH_TOKEN=\$($GENERATE_SCRIPT --fleet-id $EXAMPLE_FLEET_ID --compute-name $EXAMPLE_COMPUTE_NAME)"
echo "export GAMELIFT_SDK_AUTH_TOKEN=\"\$AUTH_TOKEN\""
echo "# Start your game server here"
echo "# ./YourGameServer"
echo ""

# Example 8: Using with Docker
print_info "Example 8: Using with Docker"
echo "# Generate token and pass to Docker container"
echo "AUTH_TOKEN=\$($GENERATE_SCRIPT --fleet-id $EXAMPLE_FLEET_ID --compute-name $EXAMPLE_COMPUTE_NAME)"
echo "docker run -e GAMELIFT_SDK_AUTH_TOKEN=\"\$AUTH_TOKEN\" your-game-server-image"
echo ""

print_success "Examples completed!"
print_info "To use with your actual fleet and compute, replace the example values with your real ones."
print_info "Run '$GENERATE_SCRIPT --help' for more options and detailed usage information."
