# GameLift SDK Authentication Token Generator

This directory contains scripts for generating GameLift SDK authentication tokens for your game servers.

## Files

- `generate_auth_token.sh` - Main script for generating GameLift SDK authentication tokens
- `example_usage.sh` - Examples showing different ways to use the generator script
- `README.md` - This documentation file

## Prerequisites

1. **AWS CLI**: Must be installed and configured with appropriate credentials
2. **jq**: JSON parser (will be installed automatically if missing on supported systems)
3. **AWS Permissions**: Your AWS credentials must have permission to call `gamelift:GetComputeAuthToken`

## Quick Start

### Basic Usage

```bash
# Generate a token for your fleet and compute
./generate_auth_token.sh --fleet-id your-fleet-id --compute-name your-compute-name
```

### Common Use Cases

#### 1. Get Token for Environment Variable

```bash
# Get token formatted for export
./generate_auth_token.sh --fleet-id fleet-123 --compute-name MyServer --output env
# Output: export GAMELIFT_SDK_AUTH_TOKEN="your-token-here"
```

#### 2. Export Token Directly

```bash
# Generate and export token in one command
./generate_auth_token.sh --fleet-id fleet-123 --compute-name MyServer --export
```

#### 3. Save Token to File

```bash
# Save token to a secure file
./generate_auth_token.sh --fleet-id fleet-123 --compute-name MyServer --save /path/to/token.txt
```

#### 4. Use with Game Server Startup

```bash
#!/bin/bash
# Get token and start game server
AUTH_TOKEN=$(./generate_auth_token.sh --fleet-id fleet-123 --compute-name MyServer)
export GAMELIFT_SDK_AUTH_TOKEN="$AUTH_TOKEN"
./YourGameServer
```

## Command Line Options

| Option | Description | Required |
|--------|-------------|----------|
| `-f, --fleet-id` | GameLift fleet ID | Yes |
| `-c, --compute-name` | Compute name | Yes |
| `-r, --region` | AWS region (default: us-east-1) | No |
| `-o, --output` | Output format: token, env, json (default: token) | No |
| `-e, --export` | Export as environment variable | No |
| `-s, --save` | Save token to file | No |
| `-h, --help` | Show help message | No |

## Environment Variables

You can set default values using environment variables:

```bash
export GAMELIFT_FLEET_ID="your-fleet-id"
export GAMELIFT_COMPUTE_NAME="your-compute-name"
export AWS_DEFAULT_REGION="us-east-1"
```

Then run the script without parameters:

```bash
./generate_auth_token.sh
```

## Output Formats

### Token (default)
```
your-auth-token-here
```

### Environment Variable
```
export GAMELIFT_SDK_AUTH_TOKEN="your-auth-token-here"
```

### JSON
```json
{
  "AuthToken": "your-auth-token-here",
  "FleetId": "your-fleet-id",
  "ComputeName": "your-compute-name",
  "Region": "us-east-1"
}
```

## Integration Examples

### Docker Integration

```bash
# Generate token and pass to Docker container
AUTH_TOKEN=$(./generate_auth_token.sh --fleet-id fleet-123 --compute-name MyServer)
docker run -e GAMELIFT_SDK_AUTH_TOKEN="$AUTH_TOKEN" your-game-server-image
```

### CI/CD Pipeline

```bash
# In your CI/CD pipeline
AUTH_TOKEN=$(./generate_auth_token.sh --fleet-id $FLEET_ID --compute-name $COMPUTE_NAME)
echo "GAMELIFT_SDK_AUTH_TOKEN=$AUTH_TOKEN" >> $GITHUB_ENV
```

### Kubernetes Deployment

```bash
# Generate token and create Kubernetes secret
AUTH_TOKEN=$(./generate_auth_token.sh --fleet-id fleet-123 --compute-name MyServer)
kubectl create secret generic gamelift-auth --from-literal=token="$AUTH_TOKEN"
```

## Security Considerations

1. **Token Expiration**: Auth tokens are valid for a limited time (typically 3 hours). Implement token refresh logic in your application.

2. **Secure Storage**: When saving tokens to files, the script automatically sets secure permissions (600 - read/write for owner only).

3. **Environment Variables**: Be careful not to log or expose environment variables containing sensitive tokens.

4. **AWS Permissions**: Use IAM roles with minimal required permissions for your use case.

## Troubleshooting

### Common Issues

1. **"Fleet ID not found"**
   - Verify the fleet ID is correct
   - Ensure your AWS credentials have access to the fleet
   - Check the AWS region

2. **"AWS credentials not configured"**
   - Run `aws configure` to set up your credentials
   - Or use IAM roles if running on EC2

3. **"jq not found"**
   - The script will attempt to install jq automatically
   - On unsupported systems, install jq manually

### Debug Mode

To see detailed AWS CLI output, you can modify the script to remove the `2>/dev/null` redirects or add `--debug` to AWS CLI commands.

## Examples

Run the example script to see various usage patterns:

```bash
./example_usage.sh
```

## Related Documentation

- [AWS GameLift Developer Guide](https://docs.aws.amazon.com/gamelift/)
- [GetComputeAuthToken API Reference](https://docs.aws.amazon.com/gameliftservers/latest/apireference/API_GetComputeAuthToken.html)
- [GameLift SDK Documentation](https://docs.aws.amazon.com/gamelift/latest/developerguide/gamelift-supported.html)
