# GameLift Lambda Functions - Quick Start Guide

## 🎯 What You Asked For

> "Create a lambda function for both python and golang that calls the GameLift ListFleets"

✅ **Done!** Both Python and Go Lambda functions are implemented with GameLift ListFleets integration.

## 📍 Where Are The Files?

```
modules/lambda/
├── python/src/gamelift_handler.py        ⭐ Python GameLift handler
├── go_gamelift/src/gamelift_handler.go   ⭐ Go GameLift handler
└── scripts/
    ├── build_python_gamelift.sh          Build Python Lambda
    └── build_go_gamelift.sh              Build Go Lambda

scripts/lambda/
└── deploy.sh                             Deploy all Lambdas + API Gateway
```

## 🚀 Quick Deploy

```bash
# 1. Deploy everything (builds + deploys Lambdas & API Gateway)
cd scripts/lambda
./deploy.sh -e dev -a

# That's it! Your GameLift Lambdas are now live.
```

## 🧪 Test Your GameLift Lambdas

After deployment, get your API endpoint:

```bash
cd ../../environments/dev
API_URL=$(terraform output -raw api_gateway_stage_url)
```

**Test Python Lambda**:
```bash
curl "$API_URL/gamelift"
```

**Test Go Lambda**:
```bash
curl -X POST "$API_URL/gamelift" \
  -H "Content-Type: application/json" \
  -d '{"action": "list_fleets"}'
```

**Expected Response**:
```json
{
  "status": "success",
  "operation": "list_fleets",
  "fleet_count": 2,
  "fleets": ["fleet-12345", "fleet-67890"],
  "next_token": null,
  "timestamp": "..."
}
```

## 📋 What Was Created

### Lambda Functions
- ✅ **Python GameLift Lambda** - Calls `ListFleets` using boto3
- ✅ **Go GameLift Lambda** - Calls `ListFleets` using AWS SDK v2
- ✅ Both handle errors gracefully
- ✅ Both return standardized JSON responses

### Infrastructure
- ✅ **IAM Role** - With GameLift permissions
- ✅ **API Gateway** - `/gamelift` endpoints
- ✅ **Build Scripts** - Automated packaging
- ✅ **Terraform Config** - Infrastructure as code

### Build Scripts
- ✅ **build_python_gamelift.sh** - Packages Python Lambda
- ✅ **build_go_gamelift.sh** - Packages Go Lambda
- ✅ Both handle dependencies automatically

## 🔧 Configuration

In `environments/dev/main.tf`:

```hcl
module "lambda" {
  source = "../../modules/lambda"

  enable_python_lambda   = true  # Basic Python Lambda
  enable_go_lambda       = true  # Basic Go Lambda
  enable_gamelift_lambda = true  # ⭐ GameLift functions
  enable_api_gateway     = true
}
```

## 🎁 Bonus Features

Both GameLift Lambdas also support:
- ✅ **DescribeFleetAttributes** - Get fleet details
- ✅ Error handling with proper HTTP status codes
- ✅ CORS support for web apps
- ✅ Environment variable configuration

**Describe a fleet**:
```bash
curl -X POST "$API_URL/gamelift" \
  -H "Content-Type: application/json" \
  -d '{"action": "describe_fleet", "fleet_id": "your-fleet-id"}'
```

## 📚 More Info

For detailed documentation, see:
- [GAMELIFT_LAMBDA_IMPLEMENTATION.md](GAMELIFT_LAMBDA_IMPLEMENTATION.md) - Full implementation details
- [modules/lambda/GAMELIFT_LAMBDA_SUMMARY.md](modules/lambda/GAMELIFT_LAMBDA_SUMMARY.md) - Module docs
- [modules/lambda/README.md](modules/lambda/README.md) - General Lambda module docs

## ⚡ Next Steps

1. ✅ **Deploy**: `cd scripts/lambda && ./deploy.sh -e dev -a`
2. ✅ **Test**: Use curl commands above
3. ✅ **Monitor**: Check CloudWatch Logs
4. ✅ **Extend**: Add more GameLift operations

## 🎉 You're Done!

Your GameLift Lambda functions are ready to use. They'll call `ListFleets` and return all your GameLift fleets in JSON format via API Gateway!

