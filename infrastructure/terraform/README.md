# Unreal Engine 5 Terraform Infrastructure

This Terraform layout deploys AWS infrastructure for Unreal Engine 5 workflows using an environment + modules structure.

## Layout

```text
infrastructure/terraform/
├── environments/
│   └── dev/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
└── modules/
    ├── networking/
    ├── security/
    ├── compute/
    └── monitoring/
```

## Quick Start (dev)

```bash
cd UnrealEngine5DedicatedServersWithAWSAndGameLift/infrastructure/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Notes

- `environments/dev` is the Terraform root module entrypoint.
- Shared building blocks are in `modules/*`.
- Update `terraform.tfvars` with your region, CIDRs, instance type, and access restrictions before applying.
