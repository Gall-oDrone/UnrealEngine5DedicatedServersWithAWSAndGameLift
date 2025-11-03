# Lambda Module

This module provides AWS Lambda functions in both Python and Go, along with API Gateway integration for deploying serverless REST APIs.

## Overview

The Lambda module creates:
- **Python Lambda functions** with Python 3.12 runtime
- **Go Lambda functions** with AWS Lambda provided.al2023 runtime
- **GameLift Lambda functions** for Python and Go with GameLift API integration
- **API Gateway REST API** with CORS support
- **IAM roles and policies** for Lambda execution
- **Integration** between API Gateway and Lambda functions

> **Note**: For GameLift-specific Lambda functions, see [GAMELIFT_LAMBDA_SUMMARY.md](GAMELIFT_LAMBDA_SUMMARY.md)

## Structure

```
modules/lambda/
├── python/
│   ├── src/                # Python Lambda source code
│   │   ├── handler.py      # Main handler function
│   │   └── requirements.txt
│   └── tests/              # Python unit tests
│       └── test_handler.py
├── go/
│   ├── src/                # Go Lambda source code
│   │   └── main.go         # Main handler function
│   ├── go.mod              # Go module file
│   └── tests/              # Go unit tests
│       └── main_test.go
├── scripts/
│   ├── build_python.sh     # Python build script
│   └── build_go.sh         # Go build script
├── main.tf                 # Terraform configuration
├── variables.tf            # Input variables
├── outputs.tf              # Output values
└── README.md               # This file
```

## Usage

### Basic Usage

```hcl
module "lambda" {
  source = "../../modules/lambda"

  project_name         = "my-project"
  environment          = "dev"
  aws_region           = "us-east-1"
  common_tags          = local.common_tags
  
  enable_python_lambda = true
  enable_go_lambda     = true
  enable_api_gateway   = true
}
```

### Advanced Usage with VPC

```hcl
module "lambda" {
  source = "../../modules/lambda"

  project_name         = "my-project"
  environment          = "dev"
  aws_region           = "us-east-1"
  common_tags          = local.common_tags
  
  enable_python_lambda = true
  enable_go_lambda     = true
  enable_api_gateway   = true
  
  lambda_timeout       = 60
  lambda_memory_size   = 512
  
  vpc_config = {
    vpc_id             = module.networking.vpc_id
    subnet_ids         = module.networking.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_name | Name of the project | string | - | yes |
| environment | Environment name | string | - | yes |
| aws_region | AWS region | string | `"us-east-1"` | no |
| common_tags | Common tags | map(string) | `{}` | no |
| enable_python_lambda | Enable Python Lambda | bool | `true` | no |
| enable_go_lambda | Enable Go Lambda | bool | `true` | no |
| enable_api_gateway | Enable API Gateway | bool | `true` | no |
| python_lambda_runtime | Python runtime version | string | `"python3.12"` | no |
| lambda_timeout | Lambda timeout in seconds | number | `30` | no |
| lambda_memory_size | Lambda memory size in MB | number | `256` | no |
| api_gateway_stage_name | API Gateway stage name | string | `"v1"` | no |
| api_gateway_enable_cors | Enable CORS | bool | `true` | no |
| vpc_config | VPC configuration | object | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| python_lambda_arn | ARN of the Python Lambda function |
| python_lambda_function_name | Name of the Python Lambda function |
| go_lambda_arn | ARN of the Go Lambda function |
| go_lambda_function_name | Name of the Go Lambda function |
| api_gateway_url | URL of the API Gateway |
| api_gateway_stage_url | Stage URL of the API Gateway |
| python_endpoint_url | Python Lambda endpoint URL |
| go_endpoint_url | Go Lambda endpoint URL |
| lambda_execution_role_arn | ARN of the Lambda execution role |

## Prerequisites

### For Python Lambda
- Python 3.12 or later
- pip3 for installing dependencies

### For Go Lambda
- Go 1.21 or later

## Building Lambda Functions

### Local Build

```bash
# Build Python Lambda
./scripts/build_python.sh

# Build Go Lambda
./scripts/build_go.sh
```

### Automated Build

The Terraform configuration automatically builds Lambda functions during `terraform apply` using the build scripts. The build is triggered when the source code changes.

## Testing

### Python Tests

```bash
cd python
python3 -m pytest tests/ -v
```

### Go Tests

```bash
cd go
go test ./tests/ -v
```

## Deployment

See the main [deployment script](../../scripts/lambda/deploy.sh) for instructions on deploying the Lambda module.

## Examples

### Example 1: Basic REST API

Deploy both Python and Go Lambda functions with API Gateway:

```bash
cd ../../scripts/lambda
./deploy.sh -e dev -a
```

### Example 2: Build Only

Build Lambda functions without deploying:

```bash
./deploy.sh -b
```

### Example 3: Validate Only

Validate Terraform configuration without deploying:

```bash
./deploy.sh -v
```

## Monitoring

### CloudWatch Logs

Lambda functions automatically log to CloudWatch Logs:
- Python Lambda: `/aws/lambda/{project_name}-{environment}-python`
- Go Lambda: `/aws/lambda/{project_name}-{environment}-go`

### Metrics

Key metrics to monitor:
- Invocations
- Duration
- Errors
- Throttles

## Security

### IAM Permissions

The Lambda execution role includes:
- Basic Lambda execution permissions
- CloudWatch Logs permissions
- VPC access permissions (if VPC is configured)

### Best Practices

1. **Least Privilege**: Add only necessary IAM permissions
2. **Environment Variables**: Use AWS Secrets Manager for sensitive data
3. **VPC**: Use VPC for Lambda functions accessing private resources
4. **Timeouts**: Set appropriate timeouts to control costs
5. **Memory**: Right-size memory for cost optimization

## Troubleshooting

### Build Issues

**Problem**: Python build fails
- **Solution**: Ensure pip3 is installed and requirements.txt is valid

**Problem**: Go build fails
- **Solution**: Ensure Go 1.21+ is installed and go.mod is valid

### Deployment Issues

**Problem**: Terraform fails with "resource already exists"
- **Solution**: Use `terraform refresh` or check existing resources

**Problem**: API Gateway returns 502
- **Solution**: Check Lambda function logs in CloudWatch

## Contributing

When adding new Lambda functions:

1. Add handler code in `python/src/` or `go/src/`
2. Add tests in `python/tests/` or `go/tests/`
3. Update build scripts if needed
4. Update this README with usage examples

## References

- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [API Gateway Documentation](https://docs.aws.amazon.com/apigateway/)
- [Python Lambda Guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html)
- [Go Lambda Guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-golang.html)

