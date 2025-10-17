# GameLift Anywhere Scripts

This directory contains scripts to help with GameLift Anywhere deployment and management.

## Scripts Overview

### 1. `setup_game_server.sh` - Main Orchestration Script
The main script that orchestrates the entire GameLift Anywhere setup process for an EC2 instance.

**Features:**
- Takes EC2 instance ID and GameLift fleet ID as input
- Automatically creates GameLift Anywhere fleets if needed
- Automatically registers a new compute name
- Generates authentication tokens
- Creates a startup script for the game server
- Generates environment variable files (.env, JSON, YAML)
- Provides complete configuration summary
- Comprehensive cleanup and fleet management capabilities

**Usage:**
```bash
# Basic usage (auto-creates fleet if needed)
./setup_game_server.sh --instance-id i-1234567890abcdef0

# With specific fleet ID
./setup_game_server.sh --instance-id i-1234567890abcdef0 --fleet-id fleet-12345678-1234-1234-1234-123456789012

# With custom location
./setup_game_server.sh -i i-1234567890abcdef0 -f fleet-12345678-1234-1234-1234-123456789012 -l custom-production-location

# Skip registration (use existing compute)
./setup_game_server.sh -i i-1234567890abcdef0 -f fleet-12345678-1234-1234-1234-123456789012 --skip-registration -c MyExistingCompute

# Generate environment files in multiple formats
./setup_game_server.sh -i i-1234567890abcdef0 --env-formats env,json,yaml

# Cleanup operations
./setup_game_server.sh --cleanup temp
./setup_game_server.sh --cleanup all
./setup_game_server.sh --cleanup delete-fleet --cleanup-file fleet-12345678-1234-1234-1234-123456789012
./setup_game_server.sh --cleanup delete-all-fleets
```

### 2. `register_compute.sh` - Compute Registration
Registers a new compute name with GameLift Anywhere.

**Features:**
- Validates fleet ID and ensures it's an Anywhere fleet
- Auto-detects public IP addresses
- Generates random compute names with timestamps
- Checks for existing compute names to avoid conflicts
- Supports multiple output formats
- Comprehensive cleanup capabilities

**Usage:**
```bash
# Auto-generate compute name and detect IP
./register_compute.sh --fleet-id fleet-12345678-1234-1234-1234-123456789012

# Custom compute name
./register_compute.sh -f fleet-12345678-1234-1234-1234-123456789012 -c MyGameServer

# JSON output
./register_compute.sh -f fleet-12345678-1234-1234-1234-123456789012 -o json

# Cleanup operations
./register_compute.sh --cleanup temp
./register_compute.sh --cleanup all
./register_compute.sh --cleanup file --cleanup-file compute_info.json
```

### 3. `generate_auth_token.sh` - Authentication Token Generation
Generates authentication tokens for GameLift SDK.

**Features:**
- Generates auth tokens for registered computes
- Multiple output formats (token, env, json)
- Automatic token expiration warnings
- File saving capabilities
- Comprehensive cleanup capabilities

**Usage:**
```bash
# Generate token
./generate_auth_token.sh --fleet-id fleet-12345678-1234-1234-1234-123456789012 --compute-name MyCompute

# Export as environment variable
./generate_auth_token.sh -f fleet-12345678-1234-1234-1234-123456789012 -c MyCompute -e

# Save to file
./generate_auth_token.sh -f fleet-12345678-1234-1234-1234-123456789012 -c MyCompute -s token.txt

# Cleanup operations
./generate_auth_token.sh --cleanup env
./generate_auth_token.sh --cleanup all
./generate_auth_token.sh --cleanup file --cleanup-file token.txt
```

## Quick Start Guide

### 1. Prerequisites
- AWS CLI installed and configured
- EC2 instance running with public IP
- GameLift Anywhere fleet created
- `jq` installed (for JSON parsing)

### 2. Basic Setup
```bash
# Navigate to the scripts directory
cd scripts/gamelift/

# Set up a game server (this does everything)
./setup_game_server.sh --instance-id i-1234567890abcdef0 --fleet-id fleet-12345678-1234-1234-1234-123456789012

# Copy the generated startup script to your EC2 instance
scp output/start_game_server.sh ec2-user@your-instance-ip:/local/game/

# SSH into your EC2 instance and run the startup script
ssh ec2-user@your-instance-ip
cd /local/game/
./start_game_server.sh
```

### 3. Manual Setup (Step by Step)
```bash
# Step 1: Register a compute
./register_compute.sh --fleet-id fleet-12345678-1234-1234-1234-123456789012

# Step 2: Generate auth token (use compute name from step 1)
./generate_auth_token.sh --fleet-id fleet-12345678-1234-1234-1234-123456789012 --compute-name Compute-2025-01-16-14-30-25-a1b2c3d4

# Step 3: Start your game server with the token
export GAMELIFT_SDK_AUTH_TOKEN="your-generated-token"
./FPSTemplateServer -glAnywhere=true -glAnywhereAuthToken=$GAMELIFT_SDK_AUTH_TOKEN
```

## Advanced Features

### Fleet Management
The scripts now support comprehensive fleet management operations:

```bash
# Delete a specific fleet
./setup_game_server.sh --cleanup delete-fleet --cleanup-file fleet-12345678-1234-1234-1234-123456789012

# Delete all fleets (with confirmation)
./setup_game_server.sh --cleanup delete-all-fleets

# Force delete fleet with active computes
./setup_game_server.sh --cleanup delete-fleet-force --cleanup-file fleet-12345678-1234-1234-1234-123456789012

# Force delete all fleets without confirmation
./setup_game_server.sh --cleanup delete-all-fleets-force
```

### Environment Variable File Generation
Generate configuration files in multiple formats for easy deployment:

```bash
# Generate .env file
./setup_game_server.sh -i i-1234567890abcdef0 --env-formats env

# Generate JSON configuration
./setup_game_server.sh -i i-1234567890abcdef0 --env-formats json

# Generate YAML configuration
./setup_game_server.sh -i i-1234567890abcdef0 --env-formats yaml

# Generate all formats
./setup_game_server.sh -i i-1234567890abcdef0 --env-formats env,json,yaml
```

### Cleanup Operations
Comprehensive cleanup options for different scenarios:

```bash
# Clean up temporary files only
./setup_game_server.sh --cleanup temp

# Clean up environment variables
./setup_game_server.sh --cleanup env

# Clean up output directory
./setup_game_server.sh --cleanup output

# Clean up everything
./setup_game_server.sh --cleanup all

# Clean up specific files
./setup_game_server.sh --cleanup file --cleanup-file ./output/start_game_server.sh
```

## Environment Variables

You can set these environment variables to provide defaults:

```bash
export GAMELIFT_FLEET_ID="fleet-12345678-1234-1234-1234-123456789012"
export GAMELIFT_COMPUTE_NAME="MyCompute"
export GAMELIFT_LOCATION="custom-mygame-dev-location"
export AWS_DEFAULT_REGION="us-east-1"
```

## Output Files

The `setup_game_server.sh` script generates:

- `start_game_server.sh` - Complete startup script with all GameLift configuration
- `gamelift_config.txt` - Configuration summary and next steps
- `gamelift.env` - Environment variables file (when using `--env-formats env`)
- `gamelift_config.json` - JSON configuration file (when using `--env-formats json`)
- `gamelift_config.yaml` - YAML configuration file (when using `--env-formats yaml`)

## Troubleshooting

### Common Issues

1. **"Fleet not found"**
   - Ensure the fleet ID is correct
   - Verify the fleet is an "Anywhere" fleet type

2. **"Instance not found"**
   - Check the instance ID is correct
   - Ensure the instance is running
   - Verify you have permissions to access the instance

3. **"No public IP"**
   - GameLift Anywhere requires instances with public IP addresses
   - Ensure your EC2 instance has a public IP or Elastic IP

4. **"Auth token generation failed"**
   - Make sure the compute is registered and active
   - Check that the compute name matches exactly

5. **"Fleet deletion failed"**
   - Ensure you have proper AWS permissions for GameLift
   - Check if the fleet has active computes (use `--force` flag if needed)
   - Verify the fleet ID is correct

### Debug Mode

Add `--debug` to any script to see detailed output:
```bash
./setup_game_server.sh --instance-id i-1234567890abcdef0 --fleet-id fleet-12345678-1234-1234-1234-123456789012 --debug
```

## Security Notes

- Auth tokens are sensitive and expire (typically 3 hours)
- Store tokens securely and rotate them regularly
- Use IAM roles instead of hardcoded credentials when possible
- Monitor compute registration and token usage
- Fleet deletion operations are irreversible - use with caution
- Environment variable files contain sensitive information - secure them appropriately
- Use cleanup operations to remove temporary files and tokens when done

## Support

For issues with these scripts:
1. Check the troubleshooting section above
2. Review AWS GameLift Anywhere documentation
3. Check AWS CloudTrail logs for API call details
4. Verify your AWS credentials and permissions