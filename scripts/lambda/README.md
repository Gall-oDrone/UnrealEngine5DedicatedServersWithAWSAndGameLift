# Lambda Deployment Scripts

This directory contains scripts for deploying Lambda functions and API Gateway infrastructure.

## Scripts

### deploy.sh

Main deployment script for Lambda and API Gateway infrastructure.

#### Usage

```bash
./deploy.sh [OPTIONS]
```

#### Options

- `-h, --help` - Show help message
- `-e, --environment` - Environment to deploy (dev, staging, prod) [default: dev]
- `-a, --auto-approve` - Auto-approve Terraform changes
- `-b, --build-only` - Only build Lambda functions, don't deploy
- `-d, --destroy` - Destroy the Lambda infrastructure
- `-v, --validate-only` - Only validate Terraform configuration

#### Examples

```bash
# Deploy to dev environment with prompts
./deploy.sh

# Deploy with auto-approval
./deploy.sh -a

# Deploy to staging
./deploy.sh -e staging -a

# Build only (no deployment)
./deploy.sh -b

# Validate Terraform configuration
./deploy.sh -v

# Destroy infrastructure
./deploy.sh -d -a
```

#### Prerequisites

- Terraform >= 1.0
- AWS CLI configured with valid credentials
- jq for JSON parsing
- Python 3.12+ (for Python Lambda builds)
- Go 1.21+ (for Go Lambda builds)

## Workflow

The deployment script follows this workflow:

1. **Check prerequisites** - Verifies required tools are installed
2. **Validate environment** - Checks that environment directory exists
3. **Build Lambda functions** - Builds both Python and Go Lambda functions
4. **Run Terraform** - Deploys infrastructure using Terraform
5. **Display summary** - Shows deployment outputs and endpoint URLs

## What It Deploys

The script deploys the following resources:

- **IAM Role** - Lambda execution role with necessary permissions
- **Python Lambda** - Serverless function running Python 3.12
- **Go Lambda** - Serverless function running Go with provided.al2023 runtime
- **API Gateway** - REST API with integrated Lambda functions
- **Lambda Permissions** - IAM permissions for API Gateway to invoke Lambda

## Environment Integration

The Lambda module is integrated into each environment's main.tf:

```hcl
module "lambda" {
  source = "../../modules/lambda"
  
  project_name         = var.project_name
  environment          = "dev"
  aws_region           = var.aws_region
  common_tags          = local.common_tags
  
  enable_python_lambda = true
  enable_go_lambda     = true
  enable_api_gateway   = true
}
```

## Testing Lambda Functions

After deployment, test the Lambda functions:

```bash
# Get the API Gateway URL from outputs
API_URL=$(cd ../../environments/dev && terraform output -raw api_gateway_stage_url)

# Test Python Lambda
curl -X GET "$API_URL"

# Test Go Lambda
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

## Troubleshooting

### Build Fails

If Python or Go builds fail:
- Check that Python 3.12+ is installed: `python3 --version`
- Check that Go 1.21+ is installed: `go version`
- Review build script output for specific errors

### Deployment Fails

If Terraform deployment fails:
- Check AWS credentials: `aws sts get-caller-identity`
- Review Terraform output for specific errors
- Verify environment directory exists and has valid configuration

### Lambda Function Doesn't Work

If deployed Lambda functions return errors:
- Check CloudWatch Logs for error messages
- Verify Lambda function has correct IAM permissions
- Test Lambda function directly via AWS CLI:
  ```bash
  aws lambda invoke \
    --function-name my-function \
    --payload '{"test": "data"}' \
    response.json
  ```

## See Also

- [Lambda Module README](../../modules/lambda/README.md) - Detailed module documentation
- [Deployment Guide](../../docs/deployment-guides/) - General deployment guides
- [Main Deploy Script](../deployment/deploy.sh) - Full infrastructure deployment

