# Unreal Engine 5 Dedicated Servers with AWS and GameLift

A comprehensive infrastructure-as-code solution for deploying Unreal Engine 5 dedicated servers on AWS, following modern engineering best practices inspired by the [AWS AppMod Blueprints](https://github.com/aws-samples/appmod-blueprints).

## 📚 Course Reference

This project follows along with the Udemy course: **[Unreal Engine 5 Dedicated Servers with AWS and GameLift](https://www.udemy.com/course/unreal-engine-5-dedicated-servers-with-aws-and-gamelift/?couponCode=LETSLEARNNOW#reviews)**

The course provides comprehensive guidance on setting up dedicated servers for Unreal Engine 5 games using AWS services and GameLift. This repository contains the infrastructure-as-code implementation that accompanies the course material.

## 🏗️ Architecture Overview

This project provides a modular, scalable infrastructure for Unreal Engine 5 compilation and dedicated server deployment on AWS. The architecture follows modern cloud-native principles with:

- **Modular Design**: Reusable Terraform modules for different infrastructure components
- **Multi-Environment Support**: Separate configurations for dev, staging, and production
- **Security-First**: Built-in security best practices and compliance features
- **Monitoring & Observability**: Comprehensive CloudWatch monitoring and alerting
- **Cost Optimization**: Flexible instance types and storage options

### Infrastructure Components

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Infrastructure                       │
├─────────────────────────────────────────────────────────────┤
│  VPC (10.0.0.0/16)                                          │
│  ├── Public Subnets (10.0.0.0/24, 10.0.1.0/24)             │
│  │   └── EC2 Instances (Windows Server 2022)                │
│  │       ├── Root Volume (100GB GP3)                        │
│  │       ├── Data Volume (500GB GP3)                        │
│  │       └── IAM Role (CloudWatch, S3 access)               │
│  ├── Private Subnets (10.0.10.0/24, 10.0.11.0/24)          │
│  ├── Internet Gateway                                       │
│  ├── NAT Gateway (optional)                                 │
│  ├── Security Groups (RDP, WinRM, HTTP/HTTPS)               │
│  ├── CloudWatch Monitoring & Alerts                         │
│  ├── VPC Flow Logs                                          │
│  └── KMS Encryption (optional)                              │
└─────────────────────────────────────────────────────────────┘
```

## 📁 Project Structure

```
UnrealEngine5DedicatedServersWithAWSAndGameLift/
├── modules/                          # Reusable Terraform modules
│   ├── networking/                   # VPC, subnets, routing
│   ├── compute/                      # EC2 instances, IAM roles
│   ├── security/                     # Security groups, KMS, flow logs
│   └── monitoring/                   # CloudWatch, alarms, dashboards
├── environments/                     # Environment-specific configurations
│   ├── dev/                         # Development environment
│   ├── staging/                     # Staging environment
│   └── prod/                        # Production environment
├── scripts/                         # Deployment and automation scripts
│   ├── ami-builder/                 # Custom AMI creation scripts
│   ├── cleanup/                     # Infrastructure cleanup scripts
│   ├── dcv/                         # Desktop Cloud Visualization setup
│   ├── deployment/                  # Deployment automation
│   ├── installers/                  # Software installer management
│   ├── repos/                       # Repository deployment scripts
│   └── validation/                  # Configuration validation
├── docs/                           # Documentation
│   ├── architecture/               # Architecture documentation
│   ├── deployment-guides/          # Deployment guides
│   ├── security/                   # Security documentation
│   └── troubleshooting/            # Troubleshooting guides
├── terraform/                      # Legacy Terraform configuration
└── unreal-engine-5-ide-cfn.yaml   # CloudFormation template
```

## 🚀 Quick Start

### Prerequisites

- **AWS CLI** configured with appropriate permissions
- **Terraform** >= 1.0 installed
- **Git** for version control
- **Epic Games account** with Unreal Engine access

### 1. Clone and Setup

```bash
git clone <repository-url>
cd UnrealEngine5DedicatedServersWithAWSAndGameLift
```

### 2. Configure Environment

```bash
# Navigate to the dev environment
cd environments/dev

# Copy and edit the configuration
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

**Important**: Update the `allowed_cidr_blocks` with your IP address for security.

### 3. Deploy Infrastructure

```bash
# From the project root, use the deployment script
../scripts/deployment/deploy.sh dev

# Or deploy with auto-approve
../scripts/deployment/deploy.sh dev -a
```

### 4. Access Your Infrastructure

After deployment, you'll get:
- **EC2 Instance IP**: For RDP access
- **CloudWatch Dashboard**: For monitoring
- **Connection Information**: In the deployment output

## 🔧 Configuration

### Environment Variables

Each environment has its own configuration in `environments/<env>/terraform.tfvars`:

```hcl
# Project configuration
project_name = "my-ue5-compilation-dev"
aws_region   = "us-east-1"

# Compute configuration
instance_type    = "c5.2xlarge"  # Minimum recommended
root_volume_size = 100
data_volume_size = 500

# Security configuration
allowed_cidr_blocks = ["YOUR_IP_ADDRESS/32"]

# Unreal Engine configuration
unreal_engine_version = "5.4"
unreal_engine_branch  = "5.4"
```

### Instance Types

| Instance Type | vCPUs | Memory | Use Case |
|---------------|-------|--------|----------|
| c5.2xlarge    | 8     | 16 GB  | Development, small projects |
| c5.4xlarge    | 16    | 32 GB  | Medium projects |
| c5.9xlarge    | 36    | 72 GB  | Large projects, production |

## 🛠️ Usage

### Deployment Scripts

```bash
# Deploy dev environment
./scripts/deployment/deploy.sh dev

# Deploy with auto-approve
./scripts/deployment/deploy.sh dev -a

# Deploy using simple method
./scripts/deployment/deploy-simple.sh dev

# Deploy using SSM method
./scripts/deployment/deploy-simple-ssm.sh dev

# Deploy using staged approach
./scripts/deployment/deploy-staged.sh dev

# Destroy infrastructure
./scripts/deployment/deploy.sh dev -d
```

### Validation Scripts

```bash
# Validate configuration
./scripts/validation/validate.sh dev

# Validate with verbose output
./scripts/validation/validate.sh dev -v

# Skip security checks
./scripts/validation/validate.sh dev --no-security
```

### Additional Scripts

```bash
# Software Installation
./scripts/installers/setup_installers_bucket.sh          # Setup S3 bucket for installers
./scripts/installers/download_s3_installers.sh          # Download and install software
./scripts/installers/debug_cmake_download.sh            # Debug CMake installation

# Repository Management
./scripts/repos/deploy_repos_staged.sh                  # Deploy repositories to instances
./scripts/repos/deploy_openssl_ssm_doc.sh               # Deploy OpenSSL build SSM document

# AMI Building
./scripts/ami-builder/build-custom-ami.sh               # Build custom AMI
./scripts/ami-builder/cleanup-ami-builder.sh            # Cleanup AMI builder resources

# Desktop Cloud Visualization
./scripts/dcv/setup_dcv.sh                              # Setup DCV on instances
./scripts/dcv/dcv_install.ps1                           # DCV installation script

# UE 5.6 snapshot (archived) - restore BEFORE deploying, re-archive when done
./scripts/snapshot/manage_snapshot.sh status
./scripts/snapshot/manage_snapshot.sh restore --days 7 --wait   # 24-72 h, ~$13 one-time
./scripts/snapshot/manage_snapshot.sh archive                   # back to ~$5/month

# Infrastructure Cleanup (terraform destroy + tag-based sweep + VERIFICATION)
./scripts/cleanup/cleanup.sh --dry-run                  # see what would be removed
./scripts/cleanup/cleanup.sh                            # exit code != 0 if anything billable remains
```

### Manual Terraform Commands

```bash
cd environments/dev

# Initialize (remote state in S3 - see backend.hcl)
terraform init -backend-config=backend.hcl

# Plan
terraform plan

# Apply
terraform apply

# Destroy - prefer ./scripts/cleanup/cleanup.sh, which verifies afterwards
terraform destroy
```

### Restoring the UE 5.6 build environment

The 500 GB data volume (VS2022, UE 5.6 compiled from GitHub source, NVIDIA
drivers, installers) is **not** kept as a volume any more; it lives in an
EBS snapshot in the *archive* tier:

| Snapshot | Size | Tier | Cost |
|---|---|---|---|
| `snap-0777feef308067690` | 500 GB (≈421 GiB used) | archive | ~$5/month |

Set `data_volume_snapshot_id = "snap-0777feef308067690"` in `terraform.tfvars`,
run `./scripts/snapshot/manage_snapshot.sh restore` **1–3 days before** you
need the machine, and deploy once `status` reports the standard tier. The
compute module's `precondition`s refuse to create anything while the snapshot
is archived, so a premature `apply` fails fast instead of half-deploying.
Archive has a 90-day minimum (until **2027-02-02** for this snapshot).

## 🔒 Security Features

### Built-in Security

- **VPC Isolation**: Private and public subnets
- **Security Groups**: Restrictive access controls
- **IAM Roles**: Least privilege access
- **Encryption**: EBS volume encryption
- **VPC Flow Logs**: Network traffic monitoring
- **KMS Integration**: Optional additional encryption

### Security Best Practices

1. **Restrict Access**: Update `allowed_cidr_blocks` with your IP
2. **Use Key Pairs**: Configure SSH/RDP key pairs
3. **Enable KMS**: For additional encryption
4. **Monitor Logs**: Review CloudWatch logs regularly
5. **Regular Updates**: Keep AMIs and software updated

## 📊 Monitoring & Observability

### CloudWatch Dashboard

Automatically created dashboard with:
- EC2 instance metrics (CPU, memory, network)
- EBS volume performance
- Custom Unreal Engine metrics

### Alerts

Configurable alarms for:
- High CPU usage (>80%)
- High memory usage (>85%)
- High disk usage (>85%)
- Instance health checks

### Logs

- **Application Logs**: Unreal Engine compilation logs
- **Security Logs**: Access and security events
- **VPC Flow Logs**: Network traffic analysis

## 💰 Cost Optimization

### Estimated Monthly Costs

| Component | Cost Range |
|-----------|------------|
| EC2 Instance (c5.2xlarge) | $300-500 |
| EBS Volumes | $50-100 |
| NAT Gateway | $45 (if enabled) |
| CloudWatch | $5-15 |
| **Total** | **$365-680** |

### Cost Optimization Tips

1. **Use Spot Instances**: For non-critical workloads
2. **Right-size Instances**: Start with c5.2xlarge, scale as needed
3. **Optimize Storage**: Use GP3 volumes for better performance/cost
4. **Disable NAT Gateway**: If not needed for private subnets
5. **Monitor Usage**: Use AWS Cost Explorer

### Cost Guard-rails (added after a $1,160 g5.24xlarge incident)

- Multi-GPU / very large instance types are **refused** unless
  `allow_expensive_instance_types = true` is set explicitly.
- Terraform state lives in S3 (`environments/dev/backend.hcl`), so
  `destroy`/cleanup works from any machine. Local state is what made the
  previous cleanup report success while an instance kept running.
- `scripts/cleanup/cleanup.sh` keeps state if `terraform destroy` fails,
  sweeps the account by tag (instances, spot requests, volumes, FSR, EIPs,
  NAT, VPC, IAM, CloudWatch, SNS, KMS), scans the region for **any** running
  GPU instance, never deletes snapshots/AMIs unless asked, and exits
  non-zero if anything billable remains.
- Fast Snapshot Restore (`data_volume_snapshot_fsr`) costs ~$540/month
  per AZ while enabled - leave it off unless you need it.

## 🔄 Automation & Scripts

### Available Automation

The project includes comprehensive automation scripts for:
- **Infrastructure Deployment**: Multiple deployment strategies (simple, SSM, staged)
- **Software Installation**: Automated installer management via S3 and SSM
- **Repository Management**: Automated repository cloning and OpenSSL builds
- **AMI Building**: Custom AMI creation for optimized instances
- **Validation**: Configuration and infrastructure validation
- **Cleanup**: Automated resource cleanup

### Script Categories

- **Deployment Scripts**: `scripts/deployment/` - Infrastructure deployment automation
- **Installer Scripts**: `scripts/installers/` - Software installation management
- **Repository Scripts**: `scripts/repos/` - Repository and build automation
- **AMI Scripts**: `scripts/ami-builder/` - Custom AMI creation
- **DCV Scripts**: `scripts/dcv/` - Desktop Cloud Visualization setup
- **Validation Scripts**: `scripts/validation/` - Configuration validation
- **Cleanup Scripts**: `scripts/cleanup/` - Resource cleanup automation

## 📚 Documentation

### Architecture Documentation

- [Architecture Overview](docs/architecture/README.md)

### Deployment Guides

- [Development Setup](docs/deployment-guides/) - Deployment guides directory
- [Troubleshooting](docs/troubleshooting/) - Troubleshooting guides
  - [DCV Connectivity Issues](docs/troubleshooting/DCV_CONNECTIVITY_ISSUE.md)

### Script Documentation

- [Software Installers](scripts/installers/README.md) - Software installation management
- [Repository Management](scripts/repos/README.md) - Repository deployment and OpenSSL builds
- [AMI Builder](scripts/ami-builder/README.md) - Custom AMI creation
- [DCV Setup](scripts/dcv/README.md) - Desktop Cloud Visualization setup

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run validation: `./scripts/validation/validate.sh dev`
5. Test deployment: `./scripts/deployment/deploy.sh dev -a`
6. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

### Getting Help

1. **Documentation**: Check the [docs/](docs/) directory and script README files
2. **Troubleshooting**: Review [troubleshooting guides](docs/troubleshooting/)
3. **Issues**: Create an issue on GitHub
4. **Script Help**: Each script directory contains detailed README files

### Common Issues

- **Instance not accessible**: Check security groups and IP restrictions
- **High costs**: Review instance types and enable cost optimization features
- **Compilation failures**: Check Unreal Engine version compatibility
- **DCV connectivity**: See [DCV troubleshooting guide](docs/troubleshooting/DCV_CONNECTIVITY_ISSUE.md)
- **Software installation**: Check [installer documentation](scripts/installers/README.md)

## 🔗 References

- [AWS AppMod Blueprints](https://github.com/aws-samples/appmod-blueprints)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Unreal Engine Documentation](https://docs.unrealengine.com/)

---

**Note**: This infrastructure will create AWS resources that incur costs. Please review the cost estimates and monitor your AWS billing dashboard. 